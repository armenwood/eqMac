//
//  Volume.swift
//  eqMac
//
//  Created by Roman Kisil on 14/05/2018.
//  Copyright © 2018 Roman Kisil. All rights reserved.
//

import Foundation
import ReSwift
import EmitterKit
import AMCoreAudio
import AVFoundation

class Volume: StoreSubscriber {
  // MARK: - Events
  var gainChanged = EmitterKit.Event<Double>()
  var balanceChanged = EmitterKit.Event<Double>()
  var mutedChanged = EmitterKit.Event<Bool>()

  var engine: AVAudioEngine?

  var booster = AVAudioUnitEQ()
  var mixer = AVAudioMixerNode()

  // MARK: - Properties
  var gain: Double = 1 {
    didSet {
      let device: AudioDevice! = Application.selectedDevice
      let volumeSupported = device.outputVolumeSupported
      let balanceSupported = device.outputBalanceSupported
      var virtualVolume: Double = 1
      if (gain <= 1) {
        if (volumeSupported) {
          device.setVirtualMasterVolume(Float32(gain), direction: .playback)
        } else {
          virtualVolume = gain
        }

        if (balanceSupported) {
          device.setVirtualMasterBalance(Float32(Utilities.mapValue(value: balance, inMin: -1, inMax: 1, outMin: 0, outMax: 1)), direction: .playback)
          mixer.pan = 0
        } else {
          mixer.pan = Float(balance)
        }

        booster.globalGain = 0
        Driver.device!.setVirtualMasterVolume(Float32(gain), direction: .playback)
      } else { // gain > 1
        if (volumeSupported) {
          device.setVirtualMasterVolume(1.0, direction: .playback)
        }
        virtualVolume = Utilities.mapValue(value: gain, inMin: 1, inMax: 2, outMin: 0, outMax: 6)

        if (balanceSupported) {
          device.setVirtualMasterBalance(Float32(Utilities.mapValue(value: balance, inMin: -1, inMax: 1, outMin: 0, outMax: 1)), direction: .playback)
          mixer.pan = 0
        } else {
          mixer.pan = Float(balance)
        }

        Driver.device!.setVirtualMasterVolume(1, direction: .playback)
      }

      mixer.outputVolume = Float(virtualVolume)

      if (!volumeSupported) {
        Driver.device!.mute = false
        device.mute = false
      }
      
      let shouldMute = gain == 0.0
      Driver.device!.mute = shouldMute
      device.mute = shouldMute
      
      gainChanged.emit(gain)
      
      Application.ignoreNextVolumeEvent = false
      Application.ignoreNextDriverMuteEvent = false
    }
  }
  
  var muted: Bool = false {
    didSet {
      if (muted) {
        mixer.outputVolume = 0
      } else {
        (gain = gain)
      }
      mutedChanged.emit(muted)
    }
  }
  
  var balance: Double = 0 {
    didSet {
      if (balance > 1) {
        balance = 1
        return
      }
      if (balance < -1) {
        balance = -1
        return
      }
      (gain = gain)
      balanceChanged.emit(balance)
    }
  }

  // MARK: - State
  typealias StoreSubscriberStateType = VolumeState
  
  private let changeGainThread = DispatchQueue(label: "change-volume", qos: .userInteractive)
  private var latestChangeGainTask: DispatchWorkItem?
  private func performOnChangeGainThread (_ code: @escaping () -> Void) {
    latestChangeGainTask?.cancel()
    latestChangeGainTask = DispatchWorkItem(block: code)
    changeGainThread.async(execute: latestChangeGainTask!)
  }

  func newState(state: VolumeState) {
    if (state.balance != balance) {
      performOnChangeGainThread { [weak self] in
        guard self != nil else { return }
        if (state.transition) {
          Transition.perform(from: self!.balance, to: state.balance) { balance in
            self!.balance = balance
          }
        } else {
          self!.balance = state.balance
        }
      }
    }
    
    if (state.gain != gain) {
      performOnChangeGainThread { [weak self] in
        guard self != nil else { return }
        if (state.transition) {
          Transition.perform(from: self!.gain, to: state.gain) { [weak self] gain in
            self?.gain = gain
          }
        } else {
          self!.gain = state.gain
        }
      }
    }
    
    if (state.muted != muted) {
      performOnChangeGainThread { [weak self] in
        guard self != nil else { return }
        self!.muted = state.muted
      }
    }
  }
  
  // MARK: - Initialization
  init () {
    Console.log("Creating Volume")
    setupStateListener()
  }
  
  func setupStateListener () {
    Application.store.subscribe(self) { subscription in
      subscription.select { state in state.effects.volume }
    }
  }

  func attachToEngine (engine: AVAudioEngine) {
    self.engine = engine
    let format = engine.outputNode.outputFormat(forBus: 0)

    engine.attach(booster)
    engine.attach(mixer)

    engine.connect(booster, to: mixer, format: format)
  }

  func postSetup () {
    (gain = gain)
  }
  
}
