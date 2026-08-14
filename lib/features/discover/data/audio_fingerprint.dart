import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart_fft.dart';

class AudioFingerprint {
  static const int sampleRate = 8000;
  static const int fftSize = 1024;
  static const int hopSize = 256;
  static const double minFreq = 250.0;
  static const double maxFreq = 3000.0;
  static const int peaksPerFrame = 3;
  static const int maxDeltaFrames = 63;

  static String generate(Float64List pcmSamples) {
    return _generateFingerprint(pcmSamples);
  }

  static String _generateFingerprint(Float64List samples) {
    final frames = _computeFrames(samples);
    final peaks = _findPeaks(frames);
    final hashes = _generateHashes(peaks);
    return _encodeFingerprint(hashes);
  }

  static List<List<double>> _computeFrames(Float64List samples) {
    final frames = <List<double>>[];
    for (var start = 0; start + fftSize <= samples.length; start += hopSize) {
      var frame = <double>[];
      for (var i = 0; i < fftSize; i++) {
        final hann = 0.5 * (1 - cos(2 * pi * i / (fftSize - 1)));
        final idx = start + i;
        if (idx < samples.length) {
          frame.add(samples[idx] * hann);
        } else {
          frame.add(0.0);
        }
      }
      frames.add(frame);
    }
    return frames;
  }

  static int _freqToBin(double freq) {
    return ((freq / sampleRate) * fftSize).round();
  }

  static List<_Peak> _findPeaks(List<List<double>> frames) {
    final allPeaks = <_Peak>[];
    const int minBin = 3;
    final maxBin = _freqToBin(maxFreq);
    final halfN = fftSize ~/ 2;

    for (var t = 0; t < frames.length; t++) {
      final spectrum = FFT.magnitudeSpectrum(frames[t]);
      final framePeaks = <_Peak>[];

      for (var bin = minBin; bin < min(maxBin, halfN); bin++) {
        final mag = spectrum[bin];
        if (mag > 0 &&
            mag >= spectrum[bin - 1] &&
            mag >= spectrum[bin + 1] &&
            mag > 0.001) {
          framePeaks.add(_Peak(t, bin, mag));
        }
      }

      framePeaks.sort((a, b) => b.magnitude.compareTo(a.magnitude));
      allPeaks.addAll(framePeaks.take(peaksPerFrame));
    }

    return allPeaks;
  }

  static List<int> _generateHashes(List<_Peak> peaks) {
    const anchorThreshold = 1;
    final hashes = <int>[];

    for (var i = 0; i < peaks.length; i++) {
      final anchor = peaks[i];
      for (var j = i + anchorThreshold; j < min(i + maxDeltaFrames, peaks.length); j++) {
        final target = peaks[j];
        final deltaTime = target.time - anchor.time;
        if (deltaTime < 1 || deltaTime > maxDeltaFrames) continue;

        final f1 = anchor.freqBin & 0x3FF;
        final f2 = target.freqBin & 0x1FF;
        final dt = deltaTime & 0xFFF;
        final hash = (f1 << 21) | (f2 << 12) | dt;
        hashes.add(hash);
      }
    }

    return hashes;
  }

  static String _encodeFingerprint(List<int> hashes) {
    final buffer = ByteData(4 + hashes.length * 4);
    buffer.setUint32(0, hashes.length, Endian.big);

    for (var i = 0; i < hashes.length; i++) {
      buffer.setUint32(4 + i * 4, hashes[i], Endian.big);
    }

    return base64.encode(buffer.buffer.asUint8List());
  }
}

class _Peak {
  final int time;
  final int freqBin;
  final double magnitude;

  const _Peak(this.time, this.freqBin, this.magnitude);
}
