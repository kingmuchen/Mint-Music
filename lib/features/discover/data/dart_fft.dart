import 'dart:math';

class Complex {
  final double real;
  final double imag;

  const Complex(this.real, this.imag);

  Complex operator +(Complex other) => Complex(real + other.real, imag + other.imag);
  Complex operator -(Complex other) => Complex(real - other.real, imag - other.imag);
  Complex operator *(Complex other) =>
      Complex(real * other.real - imag * other.imag, real * other.imag + imag * other.real);

  double get magnitude => sqrt(real * real + imag * imag);
}

class FFT {
  static List<double> magnitudeSpectrum(List<double> samples) {
    final n = _nextPowerOfTwo(samples.length);
    final padded = List<double>.filled(n, 0.0);
    for (var i = 0; i < samples.length; i++) {
      padded[i] = samples[i];
    }

    final spectrum = _fft(padded);

    final mag = <double>[];
    for (var i = 0; i < (n ~/ 2); i++) {
      mag.add(spectrum[i].magnitude);
    }
    return mag;
  }

  static int _nextPowerOfTwo(int n) {
    var p = 1;
    while (p < n) { p <<= 1; }
    return p;
  }

  static List<Complex> _fft(List<double> realInput) {
    final n = realInput.length;
    final x = <Complex>[];
    for (var i = 0; i < n; i++) {
      x.add(Complex(realInput[i], 0.0));
    }
    _fftRecursive(x);
    return x;
  }

  static void _fftRecursive(List<Complex> x) {
    final n = x.length;
    if (n <= 1) return;

    final even = <Complex>[];
    final odd = <Complex>[];
    for (var i = 0; i < n; i += 2) {
      even.add(x[i]);
      odd.add(x[i + 1]);
    }

    _fftRecursive(even);
    _fftRecursive(odd);

    for (var k = 0; k < n ~/ 2; k++) {
      final angle = -2 * pi * k / n;
      final t = Complex(cos(angle), sin(angle)) * odd[k];
      x[k] = even[k] + t;
      x[k + n ~/ 2] = even[k] - t;
    }
  }
}
