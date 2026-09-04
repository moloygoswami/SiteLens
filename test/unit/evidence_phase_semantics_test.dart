import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/domain/models/enums.dart';

void main() {
  group('EvidencePhase Domain Semantics Tests', () {
    test('Non-Conformity maps strictly to EvidencePhase.before', () {
      expect(ObservationType.nonConformity.phase, EvidencePhase.before);
      expect(ObservationType.nonConformity.phase.isBefore, isTrue);
      expect(ObservationType.nonConformity.phase.isAfter, isFalse);
      expect(ObservationType.nonConformity.isBeforeRole, isTrue);
      expect(ObservationType.nonConformity.isAfterRole, isFalse);
    });

    test('Closed maps strictly to EvidencePhase.after', () {
      expect(ObservationType.closed.phase, EvidencePhase.after);
      expect(ObservationType.closed.phase.isAfter, isTrue);
      expect(ObservationType.closed.phase.isBefore, isFalse);
      expect(ObservationType.closed.isAfterRole, isTrue);
      expect(ObservationType.closed.isBeforeRole, isFalse);
    });

    test('Progress, Material, and General map strictly to EvidencePhase.none', () {
      for (final type in [
        ObservationType.progress,
        ObservationType.material,
        ObservationType.general,
      ]) {
        expect(type.phase, EvidencePhase.none);
        expect(type.phase.isBefore, isFalse);
        expect(type.phase.isAfter, isFalse);
        expect(type.isBeforeRole, isFalse);
        expect(type.isAfterRole, isFalse);
      }
    });

    test('String parser normalizes before and after aliases correctly', () {
      expect(ObservationType.fromString('before'), ObservationType.nonConformity);
      expect(ObservationType.fromString('BEFORE'), ObservationType.nonConformity);
      expect(ObservationType.fromString('Non-Conformity'), ObservationType.nonConformity);
      expect(ObservationType.fromString('non_conformity'), ObservationType.nonConformity);

      expect(ObservationType.fromString('after'), ObservationType.closed);
      expect(ObservationType.fromString('AFTER'), ObservationType.closed);
      expect(ObservationType.fromString('closed'), ObservationType.closed);
      expect(ObservationType.fromString('Closed'), ObservationType.closed);
    });
  });
}
