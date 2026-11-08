// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Rostyslav Fesyk

import Foundation
import CoreAudio
import AudioDSP

enum AudioProperty {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw AudioFailure(message: operation, status: status)
        }
    }
    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         initial: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> T {
        var result = initial
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutablePointer(to: &result) {
            try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0), "Could not read the audio device")
        }
        return result
    }
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var result: Unmanaged<CFString>?
        var address = address(selector)
        var size = UInt32(MemoryLayout<CFString>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result), "Could not read the device name")
        guard let result else { throw AudioFailure(message: "The audio device has no name.") }
        return result.takeRetainedValue() as String
    }
    static func channels(_ object: AudioObjectID, scope: AudioObjectPropertyScope) throws -> UInt32 {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), "Could not read audio channels")
        let memory = UnsafeMutableRawPointer.allocate(byteCount: max(Int(size), MemoryLayout<AudioBufferList>.size), alignment: 16)
        defer { memory.deallocate() }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, memory), "Could not read audio channels")
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + $1.mNumberChannels }
    }
    static func defaultOutput() throws -> AudioObjectID {
        try value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0))
    }
}

protocol AudioEngineControlling: AnyObject {
    var dsp: OpaquePointer? { get }
    var sampleRate: Double { get }
    var outputName: String { get }
    func start() throws
    func stop()
    func routeChanged() -> Bool
}

final class SystemAudioEngine: AudioEngineControlling {
    private(set) var dsp: OpaquePointer?
    private var tapDescription: CATapDescription?
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private(set) var outputID: AudioObjectID = 0
    private(set) var sampleRate = 48000.0
    private(set) var outputName = "System output"

    deinit { stop() }

    func start() throws {
        stop()
        do {
            outputID = try AudioProperty.defaultOutput()
            guard outputID != 0 else { throw AudioFailure(message: "Connect headphones or speakers and try again.") }
            let uid = try AudioProperty.string(outputID, kAudioDevicePropertyDeviceUID)
            outputName = try AudioProperty.string(outputID, kAudioObjectPropertyName)
            sampleRate = try AudioProperty.value(outputID, kAudioDevicePropertyNominalSampleRate, initial: 48000.0)
            let outChannels = try AudioProperty.channels(outputID, scope: kAudioObjectPropertyScopeOutput)
            guard outChannels == 2 else {
                throw AudioFailure(message: "This version supports stereo output. Select your Mac speakers or stereo headphones.")
            }
            var pid = getpid()
            var ownProcess = AudioObjectID(0)
            var address = AudioProperty.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            try AudioProperty.check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &ownProcess), "Could not exclude the app’s own audio")
            guard ownProcess != 0 else { throw AudioFailure(message: "Core Audio is not ready. Try turning the equalizer on again.") }

            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcess])
            description.name = "toneboy · System audio"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            tapDescription = description
            try AudioProperty.check(AudioHardwareCreateProcessTap(description, &tapID), "Could not connect to system audio")
            let format = try AudioProperty.value(tapID, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
            guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mChannelsPerFrame == 2 else {
                throw AudioFailure(message: "The system audio capture format is not supported.")
            }
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "toneboy Audio",
                kAudioAggregateDeviceUIDKey: "app.tonebar.aggregate.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                   kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: false
            ]
            try AudioProperty.check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID), "Could not create the audio route")
            var rate = sampleRate
            address = AudioProperty.address(kAudioDevicePropertyNominalSampleRate)
            try AudioProperty.check(AudioObjectSetPropertyData(aggregateID, &address, 0, nil,
                UInt32(MemoryLayout<Double>.size), &rate), "Could not synchronize the audio sample rate")
            // Aggregate input streams are physical subdevice streams followed by the stereo tap.
            // Validate the full layout before enabling mute or starting the callback.
            let physicalInputs = try AudioProperty.channels(outputID, scope: kAudioObjectPropertyScopeInput)
            let aggregateInputs = try AudioProperty.channels(aggregateID, scope: kAudioObjectPropertyScopeInput)
            guard aggregateInputs == physicalInputs + 2 else {
                throw AudioFailure(message: "Could not identify the system audio stereo channels.")
            }
            try validateStreams(scope: kAudioObjectPropertyScopeInput)
            try validateStreams(scope: kAudioObjectPropertyScopeOutput)
            guard let state = tb_create(sampleRate) else { throw AudioFailure(message: "Could not initialize audio processing.") }
            dsp = state
            tb_set_render_output(state, false)
            tb_set_input_offset(state, physicalInputs)
            try AudioProperty.check(AudioDeviceCreateIOProcID(aggregateID, tb_audio_callback, UnsafeMutableRawPointer(state), &ioProc), "Could not create the audio stream")
            // Never enable a microphone stream when a headset exposes both input and output.
            try AudioProperty.check(tb_disable_physical_inputs(aggregateID, ioProc, physicalInputs), "Could not disable microphone inputs on the audio route")
            try AudioProperty.check(AudioDeviceStart(aggregateID, ioProc), "Could not start audio")
        } catch {
            stop()
            throw error
        }
    }

    // Called only after real input samples have been observed in this live route.
    func enableProcessing() throws {
        guard let dsp, let description = tapDescription else {
            throw AudioFailure(message: "Start capture first.")
        }
        description.muteBehavior = .mutedWhenTapped
        var object = Unmanaged.passUnretained(description).toOpaque()
        var address = AudioProperty.address(kAudioTapPropertyDescription)
        do {
            try AudioProperty.check(AudioObjectSetPropertyData(tapID, &address, 0, nil,
                UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &object), "Could not enable tap muting")
            tb_set_render_output(dsp, true)
        } catch {
            stop()
            throw error
        }
    }

    private func validateStreams(scope: AudioObjectPropertyScope) throws {
        var address = AudioProperty.address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        try AudioProperty.check(AudioObjectGetPropertyDataSize(aggregateID, &address, 0, nil, &size), "Could not read audio streams")
        var streams = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        try AudioProperty.check(AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &size, &streams), "Could not read audio streams")
        guard !streams.isEmpty else { throw AudioFailure(message: "The audio device has no streams.") }
        for stream in streams {
            let f = try AudioProperty.value(stream, kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
            guard f.mFormatID == kAudioFormatLinearPCM, f.mBitsPerChannel == 32,
                  f.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  abs(f.mSampleRate-sampleRate) < 1 else {
                throw AudioFailure(message: "The audio device requires a different format. Try the built-in Mac speakers.")
            }
        }
    }

    func routeChanged() -> Bool {
        guard dsp != nil else { return false }
        guard let current = try? AudioProperty.defaultOutput(), current == outputID,
              let rate = try? AudioProperty.value(current, kAudioDevicePropertyNominalSampleRate, initial: 0.0),
              abs(rate-sampleRate) < 1 else { return true }
        return false
    }

    func stop() {
        if aggregateID != 0, let ioProc {
            AudioDeviceStop(aggregateID, ioProc)
            AudioDeviceDestroyIOProcID(aggregateID, ioProc)
        }
        ioProc = nil
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = 0
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        tapID = 0
        tapDescription = nil
        if let dsp { tb_destroy(dsp) }
        dsp = nil
    }
}
