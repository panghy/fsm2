import 'types.dart';

class NullChoiceMustBeLastException implements Exception {
  Type eventType;
  NullChoiceMustBeLastException(this.eventType);

  @override
  String toString() => "The Event ${eventType} already has a transition with a null 'choice'. Only one is allowed";
}

class InvalidTransitionException implements Exception {
  Type fromState;
  Event event;
  InvalidTransitionException(this.fromState, this.event);

  @override
  String toString() => 'There is no tranisition for Event ${event.runtimeType} from the State ${fromState}.';
}

class UnknownStateException implements Exception {
  String message;

  UnknownStateException(this.message);

  @override
  String toString() => message;
}