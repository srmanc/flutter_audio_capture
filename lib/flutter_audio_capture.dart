import 'dart:async';

import 'package:flutter/services.dart';

const AUDIO_CAPTURE_EVENT_CHANNEL_NAME = "ymd.dev/audio_capture_event_channel";
const AUDIO_CAPTURE_METHOD_CHANNEL_NAME = "ymd.dev/audio_capture_method_channel";

const ANDROID_AUDIOSRC_DEFAULT = 0;
const ANDROID_AUDIOSRC_MIC = 1;
const ANDROID_AUDIOSRC_CAMCORDER = 5;
const ANDROID_AUDIOSRC_VOICERECOGNITION = 6;
const ANDROID_AUDIOSRC_VOICECOMMUNICATION = 7;
const ANDROID_AUDIOSRC_UNPROCESSED = 9;

class FlutterAudioCapture {
  static const _audioCaptureEventChannel = EventChannel(AUDIO_CAPTURE_EVENT_CHANNEL_NAME);
  // ignore: cancel_subscriptions
  StreamSubscription? _audioCaptureEventChannelSubscription;

  static const _audioCaptureMethodChannel = MethodChannel(AUDIO_CAPTURE_METHOD_CHANNEL_NAME);

  double? _actualSampleRate;

  Future<void> start(Function listener, Function onError,
      {int sampleRate = 44000, int bufferSize = 5000, int audioSource = ANDROID_AUDIOSRC_DEFAULT}) async {
    if (_audioCaptureEventChannelSubscription != null) return;
    final stream = _audioCaptureEventChannel.receiveBroadcastStream({
      "sampleRate": sampleRate,
      "bufferSize": bufferSize,
      "audioSource": audioSource,
    });

    // wait for the first data, then we know we have actual values
    final initCompleter = Completer<void>();
    _actualSampleRate = null;

    // be careful here: _audioCaptureEventChannel exists the whole time, callback may be called
    // from what was already there when we called "listen" - so wait until "getSampleRate" returns
    // meaningful value or we timeout
    final tempListener = stream.listen(
      (_) async {
        if ((_actualSampleRate ?? 0) < 10) {
          _actualSampleRate = await _audioCaptureMethodChannel.invokeMethod<double>("getSampleRate");
          if ((_actualSampleRate ?? 0) >= 10 && !initCompleter.isCompleted) //
            initCompleter.complete();
        }
      },
      onError: (Object e) {
        print('Microphone init error $e');
        if (!initCompleter.isCompleted) //
          initCompleter.complete();
      },
    );

    // wait until first data processed (or timeout)
    await initCompleter.future.timeout(
      Duration(seconds: 1),
      onTimeout: () => null,
    );
    await tempListener.cancel();

    // start listening
    if (_actualSampleRate != null && _actualSampleRate! > 0) //
      _audioCaptureEventChannelSubscription = stream.listen(listener as void Function(dynamic)?, onError: onError);
  }

  Future<void> stop() async {
    if (_audioCaptureEventChannelSubscription == null) //
      return;
    final tempListener = _audioCaptureEventChannelSubscription;
    _audioCaptureEventChannelSubscription = null;
    await tempListener!.cancel();
  }

  double? get actualSampleRate => _actualSampleRate;
}
