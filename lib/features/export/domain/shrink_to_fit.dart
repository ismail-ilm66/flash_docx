/// Max file size (round 4, feature 2): finds the best-looking JPEG settings
/// whose PDF fits under a byte limit.
///
/// Order, stopping at the first fit:
/// 1. 2000 px long edge, JPEG quality 85, 80, … 55.
/// 2. The long edge 15 % smaller per step, down to 1100 px, qualities again.
/// 3. Nothing fits in colour: ask to switch to black and white
///    ([ShrinkNeedsGrayscale]); in grayscale, [ShrinkCantFit].
library;

import 'package:equatable/equatable.dart';

class ShrinkStep extends Equatable {
  const ShrinkStep(this.longEdge, this.quality, {this.grayscale = false});

  final int longEdge;
  final int quality;
  final bool grayscale;

  /// "Small text may be hard to read."
  bool get hardToRead => longEdge < 1400 || quality < 60;

  @override
  List<Object?> get props => [longEdge, quality, grayscale];

  @override
  String toString() =>
      'ShrinkStep($longEdge px, q$quality${grayscale ? ', gray' : ''})';
}

sealed class ShrinkOutcome {
  const ShrinkOutcome();
}

class ShrinkFits extends ShrinkOutcome {
  const ShrinkFits(this.step, this.bytes);
  final ShrinkStep step;
  final int bytes;
}

/// Colour can't fit even at the smallest settings; grayscale might.
class ShrinkNeedsGrayscale extends ShrinkOutcome {
  const ShrinkNeedsGrayscale(this.smallestBytes);
  final int smallestBytes;
}

/// Can't fit without making it unreadable.
class ShrinkCantFit extends ShrinkOutcome {
  const ShrinkCantFit(this.smallestBytes);
  final int smallestBytes;
}

abstract final class ShrinkToFit {
  static const startEdge = 2000;

  /// Pages stop at 1100 px (text stays readable); a passport photo may go
  /// down to [photoMinEdge] for strict upload limits.
  static const minEdge = 1100;
  static const photoMinEdge = 240;
  static const qualities = [85, 80, 75, 70, 65, 60, 55];

  /// 2000, 1700, 1445, 1228, 1100 (or on down to [min]).
  static List<int> edgesDownTo(int min) {
    final out = <int>[];
    for (var e = startEdge; e > min; e = (e * 0.85).round()) {
      out.add(e);
    }
    return out..add(min);
  }

  static List<int> get edges => edgesDownTo(minEdge);

  /// Every step in the order the plan tries them.
  static List<ShrinkStep> steps({bool grayscale = false, int min = minEdge}) =>
      [
        for (final e in edgesDownTo(min))
          for (final q in qualities) ShrinkStep(e, q, grayscale: grayscale),
      ];

  /// Runs the search with [measure] returning the PDF size for a step.
  ///
  /// The result equals trying [steps] in order, but sizes only grow with
  /// quality, so an edge whose lowest quality is too big is skipped after one
  /// measurement: about 12 measurements instead of 35.
  static ShrinkOutcome search(
    int targetBytes,
    int Function(ShrinkStep) measure, {
    bool grayscale = false,
    int min = minEdge,
  }) {
    var smallest = -1;
    for (final e in edgesDownTo(min)) {
      final floor = measure(
        ShrinkStep(e, qualities.last, grayscale: grayscale),
      );
      if (smallest < 0 || floor < smallest) smallest = floor;
      if (floor > targetBytes) continue;
      for (final q in qualities) {
        final step = ShrinkStep(e, q, grayscale: grayscale);
        final bytes = q == qualities.last ? floor : measure(step);
        if (bytes <= targetBytes) return ShrinkFits(step, bytes);
      }
    }
    return grayscale ? ShrinkCantFit(smallest) : ShrinkNeedsGrayscale(smallest);
  }
}
