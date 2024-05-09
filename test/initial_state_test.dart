import 'package:fsm2/fsm2.dart';
import 'package:test/test.dart';

import 'watcher.mocks.dart';

void main() {
  test('initialState for abstract states', () async {
    final watcher = MockWatcher();
    final machine = await createMachine(watcher);
    await machine.complete;

    // starting from ParentState should also turn on ChildStateA
    expect(await machine.isInState<ParentState>(), isTrue);
    expect(await machine.isInState<ChildStateA>(), isTrue);

    machine.applyEvent(GoToStateB());
    await machine.complete;

    expect(await machine.isInState<ParentState>(), isTrue);
    expect(await machine.isInState<ChildStateB>(), isTrue);
    // initialState of ChildStateB is ChildStateC
    expect(await machine.isInState<ChildStateC>(), isTrue);

    // no-op
    machine.applyEvent(GoToStateC());
    await machine.complete;

    expect(await machine.isInState<ParentState>(), isTrue);
    expect(await machine.isInState<ChildStateB>(), isTrue);
    expect(await machine.isInState<ChildStateC>(), isTrue);
  }, skip: false);
}

Future<StateMachine> createMachine(MockWatcher watcher) async {
  final machine = await StateMachine.create((g) => g
    ..initialState<ParentState>()
    ..state<ParentState>((b) => b
      ..initialState<ChildStateA>()
      ..on<GoToStateA, ChildStateA>()
      ..on<GoToStateB, ChildStateB>()
      ..state<ChildStateA>((b) => b)
      ..state<ChildStateB>((b) => b
        ..initialState<ChildStateC>()
        ..on<GoToStateC, ChildStateC>()
        ..state<ChildStateC>((b) => b)))
    // ignore: avoid_print
    ..onTransition((from, e, to) => print(
        '''Received Event $e in State ${from!.stateType} transitioning to State ${to!.stateType}''')));

  return machine;
}

class ParentState extends State {}

class ChildStateA extends State {}

class ChildStateB extends State {}

class ChildStateC extends State {}

class GoToStateA extends Event {}

class GoToStateB extends Event {}

class GoToStateC extends Event {}
