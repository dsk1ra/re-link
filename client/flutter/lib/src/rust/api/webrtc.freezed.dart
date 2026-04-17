// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'webrtc.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$WebRtcEvent {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WebRtcEventCopyWith<$Res> {
  factory $WebRtcEventCopyWith(
    WebRtcEvent value,
    $Res Function(WebRtcEvent) then,
  ) = _$WebRtcEventCopyWithImpl<$Res, WebRtcEvent>;
}

/// @nodoc
class _$WebRtcEventCopyWithImpl<$Res, $Val extends WebRtcEvent>
    implements $WebRtcEventCopyWith<$Res> {
  _$WebRtcEventCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$WebRtcEvent_ConnectionStateChangedImplCopyWith<$Res> {
  factory _$$WebRtcEvent_ConnectionStateChangedImplCopyWith(
    _$WebRtcEvent_ConnectionStateChangedImpl value,
    $Res Function(_$WebRtcEvent_ConnectionStateChangedImpl) then,
  ) = __$$WebRtcEvent_ConnectionStateChangedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String state});
}

/// @nodoc
class __$$WebRtcEvent_ConnectionStateChangedImplCopyWithImpl<$Res>
    extends
        _$WebRtcEventCopyWithImpl<
          $Res,
          _$WebRtcEvent_ConnectionStateChangedImpl
        >
    implements _$$WebRtcEvent_ConnectionStateChangedImplCopyWith<$Res> {
  __$$WebRtcEvent_ConnectionStateChangedImplCopyWithImpl(
    _$WebRtcEvent_ConnectionStateChangedImpl _value,
    $Res Function(_$WebRtcEvent_ConnectionStateChangedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? state = null}) {
    return _then(
      _$WebRtcEvent_ConnectionStateChangedImpl(
        state: null == state
            ? _value.state
            : state // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_ConnectionStateChangedImpl
    extends WebRtcEvent_ConnectionStateChanged {
  const _$WebRtcEvent_ConnectionStateChangedImpl({required this.state})
    : super._();

  @override
  final String state;

  @override
  String toString() {
    return 'WebRtcEvent.connectionStateChanged(state: $state)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_ConnectionStateChangedImpl &&
            (identical(other.state, state) || other.state == state));
  }

  @override
  int get hashCode => Object.hash(runtimeType, state);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_ConnectionStateChangedImplCopyWith<
    _$WebRtcEvent_ConnectionStateChangedImpl
  >
  get copyWith =>
      __$$WebRtcEvent_ConnectionStateChangedImplCopyWithImpl<
        _$WebRtcEvent_ConnectionStateChangedImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return connectionStateChanged(state);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return connectionStateChanged?.call(state);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (connectionStateChanged != null) {
      return connectionStateChanged(state);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return connectionStateChanged(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return connectionStateChanged?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (connectionStateChanged != null) {
      return connectionStateChanged(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_ConnectionStateChanged extends WebRtcEvent {
  const factory WebRtcEvent_ConnectionStateChanged({
    required final String state,
  }) = _$WebRtcEvent_ConnectionStateChangedImpl;
  const WebRtcEvent_ConnectionStateChanged._() : super._();

  String get state;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_ConnectionStateChangedImplCopyWith<
    _$WebRtcEvent_ConnectionStateChangedImpl
  >
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_DataChannelStateChangedImplCopyWith<$Res> {
  factory _$$WebRtcEvent_DataChannelStateChangedImplCopyWith(
    _$WebRtcEvent_DataChannelStateChangedImpl value,
    $Res Function(_$WebRtcEvent_DataChannelStateChangedImpl) then,
  ) = __$$WebRtcEvent_DataChannelStateChangedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String label, String state});
}

/// @nodoc
class __$$WebRtcEvent_DataChannelStateChangedImplCopyWithImpl<$Res>
    extends
        _$WebRtcEventCopyWithImpl<
          $Res,
          _$WebRtcEvent_DataChannelStateChangedImpl
        >
    implements _$$WebRtcEvent_DataChannelStateChangedImplCopyWith<$Res> {
  __$$WebRtcEvent_DataChannelStateChangedImplCopyWithImpl(
    _$WebRtcEvent_DataChannelStateChangedImpl _value,
    $Res Function(_$WebRtcEvent_DataChannelStateChangedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? label = null, Object? state = null}) {
    return _then(
      _$WebRtcEvent_DataChannelStateChangedImpl(
        label: null == label
            ? _value.label
            : label // ignore: cast_nullable_to_non_nullable
                  as String,
        state: null == state
            ? _value.state
            : state // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_DataChannelStateChangedImpl
    extends WebRtcEvent_DataChannelStateChanged {
  const _$WebRtcEvent_DataChannelStateChangedImpl({
    required this.label,
    required this.state,
  }) : super._();

  @override
  final String label;
  @override
  final String state;

  @override
  String toString() {
    return 'WebRtcEvent.dataChannelStateChanged(label: $label, state: $state)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_DataChannelStateChangedImpl &&
            (identical(other.label, label) || other.label == label) &&
            (identical(other.state, state) || other.state == state));
  }

  @override
  int get hashCode => Object.hash(runtimeType, label, state);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_DataChannelStateChangedImplCopyWith<
    _$WebRtcEvent_DataChannelStateChangedImpl
  >
  get copyWith =>
      __$$WebRtcEvent_DataChannelStateChangedImplCopyWithImpl<
        _$WebRtcEvent_DataChannelStateChangedImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return dataChannelStateChanged(label, state);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return dataChannelStateChanged?.call(label, state);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (dataChannelStateChanged != null) {
      return dataChannelStateChanged(label, state);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return dataChannelStateChanged(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return dataChannelStateChanged?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (dataChannelStateChanged != null) {
      return dataChannelStateChanged(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_DataChannelStateChanged extends WebRtcEvent {
  const factory WebRtcEvent_DataChannelStateChanged({
    required final String label,
    required final String state,
  }) = _$WebRtcEvent_DataChannelStateChangedImpl;
  const WebRtcEvent_DataChannelStateChanged._() : super._();

  String get label;
  String get state;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_DataChannelStateChangedImplCopyWith<
    _$WebRtcEvent_DataChannelStateChangedImpl
  >
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_LocalIceCandidateImplCopyWith<$Res> {
  factory _$$WebRtcEvent_LocalIceCandidateImplCopyWith(
    _$WebRtcEvent_LocalIceCandidateImpl value,
    $Res Function(_$WebRtcEvent_LocalIceCandidateImpl) then,
  ) = __$$WebRtcEvent_LocalIceCandidateImplCopyWithImpl<$Res>;
  @useResult
  $Res call({IceCandidateDto candidate});
}

/// @nodoc
class __$$WebRtcEvent_LocalIceCandidateImplCopyWithImpl<$Res>
    extends _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_LocalIceCandidateImpl>
    implements _$$WebRtcEvent_LocalIceCandidateImplCopyWith<$Res> {
  __$$WebRtcEvent_LocalIceCandidateImplCopyWithImpl(
    _$WebRtcEvent_LocalIceCandidateImpl _value,
    $Res Function(_$WebRtcEvent_LocalIceCandidateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? candidate = null}) {
    return _then(
      _$WebRtcEvent_LocalIceCandidateImpl(
        candidate: null == candidate
            ? _value.candidate
            : candidate // ignore: cast_nullable_to_non_nullable
                  as IceCandidateDto,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_LocalIceCandidateImpl
    extends WebRtcEvent_LocalIceCandidate {
  const _$WebRtcEvent_LocalIceCandidateImpl({required this.candidate})
    : super._();

  @override
  final IceCandidateDto candidate;

  @override
  String toString() {
    return 'WebRtcEvent.localIceCandidate(candidate: $candidate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_LocalIceCandidateImpl &&
            (identical(other.candidate, candidate) ||
                other.candidate == candidate));
  }

  @override
  int get hashCode => Object.hash(runtimeType, candidate);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_LocalIceCandidateImplCopyWith<
    _$WebRtcEvent_LocalIceCandidateImpl
  >
  get copyWith =>
      __$$WebRtcEvent_LocalIceCandidateImplCopyWithImpl<
        _$WebRtcEvent_LocalIceCandidateImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return localIceCandidate(candidate);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return localIceCandidate?.call(candidate);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (localIceCandidate != null) {
      return localIceCandidate(candidate);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return localIceCandidate(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return localIceCandidate?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (localIceCandidate != null) {
      return localIceCandidate(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_LocalIceCandidate extends WebRtcEvent {
  const factory WebRtcEvent_LocalIceCandidate({
    required final IceCandidateDto candidate,
  }) = _$WebRtcEvent_LocalIceCandidateImpl;
  const WebRtcEvent_LocalIceCandidate._() : super._();

  IceCandidateDto get candidate;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_LocalIceCandidateImplCopyWith<
    _$WebRtcEvent_LocalIceCandidateImpl
  >
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_RenegotiationOfferImplCopyWith<$Res> {
  factory _$$WebRtcEvent_RenegotiationOfferImplCopyWith(
    _$WebRtcEvent_RenegotiationOfferImpl value,
    $Res Function(_$WebRtcEvent_RenegotiationOfferImpl) then,
  ) = __$$WebRtcEvent_RenegotiationOfferImplCopyWithImpl<$Res>;
  @useResult
  $Res call({SessionDescriptionDto description});
}

/// @nodoc
class __$$WebRtcEvent_RenegotiationOfferImplCopyWithImpl<$Res>
    extends
        _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_RenegotiationOfferImpl>
    implements _$$WebRtcEvent_RenegotiationOfferImplCopyWith<$Res> {
  __$$WebRtcEvent_RenegotiationOfferImplCopyWithImpl(
    _$WebRtcEvent_RenegotiationOfferImpl _value,
    $Res Function(_$WebRtcEvent_RenegotiationOfferImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? description = null}) {
    return _then(
      _$WebRtcEvent_RenegotiationOfferImpl(
        description: null == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as SessionDescriptionDto,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_RenegotiationOfferImpl
    extends WebRtcEvent_RenegotiationOffer {
  const _$WebRtcEvent_RenegotiationOfferImpl({required this.description})
    : super._();

  @override
  final SessionDescriptionDto description;

  @override
  String toString() {
    return 'WebRtcEvent.renegotiationOffer(description: $description)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_RenegotiationOfferImpl &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @override
  int get hashCode => Object.hash(runtimeType, description);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_RenegotiationOfferImplCopyWith<
    _$WebRtcEvent_RenegotiationOfferImpl
  >
  get copyWith =>
      __$$WebRtcEvent_RenegotiationOfferImplCopyWithImpl<
        _$WebRtcEvent_RenegotiationOfferImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return renegotiationOffer(description);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return renegotiationOffer?.call(description);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (renegotiationOffer != null) {
      return renegotiationOffer(description);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return renegotiationOffer(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return renegotiationOffer?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (renegotiationOffer != null) {
      return renegotiationOffer(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_RenegotiationOffer extends WebRtcEvent {
  const factory WebRtcEvent_RenegotiationOffer({
    required final SessionDescriptionDto description,
  }) = _$WebRtcEvent_RenegotiationOfferImpl;
  const WebRtcEvent_RenegotiationOffer._() : super._();

  SessionDescriptionDto get description;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_RenegotiationOfferImplCopyWith<
    _$WebRtcEvent_RenegotiationOfferImpl
  >
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_RenegotiationAnswerImplCopyWith<$Res> {
  factory _$$WebRtcEvent_RenegotiationAnswerImplCopyWith(
    _$WebRtcEvent_RenegotiationAnswerImpl value,
    $Res Function(_$WebRtcEvent_RenegotiationAnswerImpl) then,
  ) = __$$WebRtcEvent_RenegotiationAnswerImplCopyWithImpl<$Res>;
  @useResult
  $Res call({SessionDescriptionDto description});
}

/// @nodoc
class __$$WebRtcEvent_RenegotiationAnswerImplCopyWithImpl<$Res>
    extends
        _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_RenegotiationAnswerImpl>
    implements _$$WebRtcEvent_RenegotiationAnswerImplCopyWith<$Res> {
  __$$WebRtcEvent_RenegotiationAnswerImplCopyWithImpl(
    _$WebRtcEvent_RenegotiationAnswerImpl _value,
    $Res Function(_$WebRtcEvent_RenegotiationAnswerImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? description = null}) {
    return _then(
      _$WebRtcEvent_RenegotiationAnswerImpl(
        description: null == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as SessionDescriptionDto,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_RenegotiationAnswerImpl
    extends WebRtcEvent_RenegotiationAnswer {
  const _$WebRtcEvent_RenegotiationAnswerImpl({required this.description})
    : super._();

  @override
  final SessionDescriptionDto description;

  @override
  String toString() {
    return 'WebRtcEvent.renegotiationAnswer(description: $description)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_RenegotiationAnswerImpl &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @override
  int get hashCode => Object.hash(runtimeType, description);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_RenegotiationAnswerImplCopyWith<
    _$WebRtcEvent_RenegotiationAnswerImpl
  >
  get copyWith =>
      __$$WebRtcEvent_RenegotiationAnswerImplCopyWithImpl<
        _$WebRtcEvent_RenegotiationAnswerImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return renegotiationAnswer(description);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return renegotiationAnswer?.call(description);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (renegotiationAnswer != null) {
      return renegotiationAnswer(description);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return renegotiationAnswer(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return renegotiationAnswer?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (renegotiationAnswer != null) {
      return renegotiationAnswer(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_RenegotiationAnswer extends WebRtcEvent {
  const factory WebRtcEvent_RenegotiationAnswer({
    required final SessionDescriptionDto description,
  }) = _$WebRtcEvent_RenegotiationAnswerImpl;
  const WebRtcEvent_RenegotiationAnswer._() : super._();

  SessionDescriptionDto get description;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_RenegotiationAnswerImplCopyWith<
    _$WebRtcEvent_RenegotiationAnswerImpl
  >
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_RenegotiationIceImplCopyWith<$Res> {
  factory _$$WebRtcEvent_RenegotiationIceImplCopyWith(
    _$WebRtcEvent_RenegotiationIceImpl value,
    $Res Function(_$WebRtcEvent_RenegotiationIceImpl) then,
  ) = __$$WebRtcEvent_RenegotiationIceImplCopyWithImpl<$Res>;
  @useResult
  $Res call({IceCandidateDto candidate});
}

/// @nodoc
class __$$WebRtcEvent_RenegotiationIceImplCopyWithImpl<$Res>
    extends _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_RenegotiationIceImpl>
    implements _$$WebRtcEvent_RenegotiationIceImplCopyWith<$Res> {
  __$$WebRtcEvent_RenegotiationIceImplCopyWithImpl(
    _$WebRtcEvent_RenegotiationIceImpl _value,
    $Res Function(_$WebRtcEvent_RenegotiationIceImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? candidate = null}) {
    return _then(
      _$WebRtcEvent_RenegotiationIceImpl(
        candidate: null == candidate
            ? _value.candidate
            : candidate // ignore: cast_nullable_to_non_nullable
                  as IceCandidateDto,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_RenegotiationIceImpl extends WebRtcEvent_RenegotiationIce {
  const _$WebRtcEvent_RenegotiationIceImpl({required this.candidate})
    : super._();

  @override
  final IceCandidateDto candidate;

  @override
  String toString() {
    return 'WebRtcEvent.renegotiationIce(candidate: $candidate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_RenegotiationIceImpl &&
            (identical(other.candidate, candidate) ||
                other.candidate == candidate));
  }

  @override
  int get hashCode => Object.hash(runtimeType, candidate);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_RenegotiationIceImplCopyWith<
    _$WebRtcEvent_RenegotiationIceImpl
  >
  get copyWith =>
      __$$WebRtcEvent_RenegotiationIceImplCopyWithImpl<
        _$WebRtcEvent_RenegotiationIceImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return renegotiationIce(candidate);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return renegotiationIce?.call(candidate);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (renegotiationIce != null) {
      return renegotiationIce(candidate);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return renegotiationIce(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return renegotiationIce?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (renegotiationIce != null) {
      return renegotiationIce(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_RenegotiationIce extends WebRtcEvent {
  const factory WebRtcEvent_RenegotiationIce({
    required final IceCandidateDto candidate,
  }) = _$WebRtcEvent_RenegotiationIceImpl;
  const WebRtcEvent_RenegotiationIce._() : super._();

  IceCandidateDto get candidate;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_RenegotiationIceImplCopyWith<
    _$WebRtcEvent_RenegotiationIceImpl
  >
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_ScreenShareStoppedImplCopyWith<$Res> {
  factory _$$WebRtcEvent_ScreenShareStoppedImplCopyWith(
    _$WebRtcEvent_ScreenShareStoppedImpl value,
    $Res Function(_$WebRtcEvent_ScreenShareStoppedImpl) then,
  ) = __$$WebRtcEvent_ScreenShareStoppedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$WebRtcEvent_ScreenShareStoppedImplCopyWithImpl<$Res>
    extends
        _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_ScreenShareStoppedImpl>
    implements _$$WebRtcEvent_ScreenShareStoppedImplCopyWith<$Res> {
  __$$WebRtcEvent_ScreenShareStoppedImplCopyWithImpl(
    _$WebRtcEvent_ScreenShareStoppedImpl _value,
    $Res Function(_$WebRtcEvent_ScreenShareStoppedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$WebRtcEvent_ScreenShareStoppedImpl
    extends WebRtcEvent_ScreenShareStopped {
  const _$WebRtcEvent_ScreenShareStoppedImpl() : super._();

  @override
  String toString() {
    return 'WebRtcEvent.screenShareStopped()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_ScreenShareStoppedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return screenShareStopped();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return screenShareStopped?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (screenShareStopped != null) {
      return screenShareStopped();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return screenShareStopped(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return screenShareStopped?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (screenShareStopped != null) {
      return screenShareStopped(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_ScreenShareStopped extends WebRtcEvent {
  const factory WebRtcEvent_ScreenShareStopped() =
      _$WebRtcEvent_ScreenShareStoppedImpl;
  const WebRtcEvent_ScreenShareStopped._() : super._();
}

/// @nodoc
abstract class _$$WebRtcEvent_FileTransferRequestedImplCopyWith<$Res> {
  factory _$$WebRtcEvent_FileTransferRequestedImplCopyWith(
    _$WebRtcEvent_FileTransferRequestedImpl value,
    $Res Function(_$WebRtcEvent_FileTransferRequestedImpl) then,
  ) = __$$WebRtcEvent_FileTransferRequestedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$WebRtcEvent_FileTransferRequestedImplCopyWithImpl<$Res>
    extends
        _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_FileTransferRequestedImpl>
    implements _$$WebRtcEvent_FileTransferRequestedImplCopyWith<$Res> {
  __$$WebRtcEvent_FileTransferRequestedImplCopyWithImpl(
    _$WebRtcEvent_FileTransferRequestedImpl _value,
    $Res Function(_$WebRtcEvent_FileTransferRequestedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$WebRtcEvent_FileTransferRequestedImpl
    extends WebRtcEvent_FileTransferRequested {
  const _$WebRtcEvent_FileTransferRequestedImpl() : super._();

  @override
  String toString() {
    return 'WebRtcEvent.fileTransferRequested()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_FileTransferRequestedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return fileTransferRequested();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return fileTransferRequested?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (fileTransferRequested != null) {
      return fileTransferRequested();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return fileTransferRequested(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return fileTransferRequested?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (fileTransferRequested != null) {
      return fileTransferRequested(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_FileTransferRequested extends WebRtcEvent {
  const factory WebRtcEvent_FileTransferRequested() =
      _$WebRtcEvent_FileTransferRequestedImpl;
  const WebRtcEvent_FileTransferRequested._() : super._();
}

/// @nodoc
abstract class _$$WebRtcEvent_SessionClosedImplCopyWith<$Res> {
  factory _$$WebRtcEvent_SessionClosedImplCopyWith(
    _$WebRtcEvent_SessionClosedImpl value,
    $Res Function(_$WebRtcEvent_SessionClosedImpl) then,
  ) = __$$WebRtcEvent_SessionClosedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String? id, String? reason});
}

/// @nodoc
class __$$WebRtcEvent_SessionClosedImplCopyWithImpl<$Res>
    extends _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_SessionClosedImpl>
    implements _$$WebRtcEvent_SessionClosedImplCopyWith<$Res> {
  __$$WebRtcEvent_SessionClosedImplCopyWithImpl(
    _$WebRtcEvent_SessionClosedImpl _value,
    $Res Function(_$WebRtcEvent_SessionClosedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? id = freezed, Object? reason = freezed}) {
    return _then(
      _$WebRtcEvent_SessionClosedImpl(
        id: freezed == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String?,
        reason: freezed == reason
            ? _value.reason
            : reason // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_SessionClosedImpl extends WebRtcEvent_SessionClosed {
  const _$WebRtcEvent_SessionClosedImpl({this.id, this.reason}) : super._();

  @override
  final String? id;
  @override
  final String? reason;

  @override
  String toString() {
    return 'WebRtcEvent.sessionClosed(id: $id, reason: $reason)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_SessionClosedImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.reason, reason) || other.reason == reason));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, reason);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_SessionClosedImplCopyWith<_$WebRtcEvent_SessionClosedImpl>
  get copyWith =>
      __$$WebRtcEvent_SessionClosedImplCopyWithImpl<
        _$WebRtcEvent_SessionClosedImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return sessionClosed(id, reason);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return sessionClosed?.call(id, reason);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (sessionClosed != null) {
      return sessionClosed(id, reason);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return sessionClosed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return sessionClosed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (sessionClosed != null) {
      return sessionClosed(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_SessionClosed extends WebRtcEvent {
  const factory WebRtcEvent_SessionClosed({
    final String? id,
    final String? reason,
  }) = _$WebRtcEvent_SessionClosedImpl;
  const WebRtcEvent_SessionClosed._() : super._();

  String? get id;
  String? get reason;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_SessionClosedImplCopyWith<_$WebRtcEvent_SessionClosedImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_SessionClosedAckImplCopyWith<$Res> {
  factory _$$WebRtcEvent_SessionClosedAckImplCopyWith(
    _$WebRtcEvent_SessionClosedAckImpl value,
    $Res Function(_$WebRtcEvent_SessionClosedAckImpl) then,
  ) = __$$WebRtcEvent_SessionClosedAckImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String? id});
}

/// @nodoc
class __$$WebRtcEvent_SessionClosedAckImplCopyWithImpl<$Res>
    extends _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_SessionClosedAckImpl>
    implements _$$WebRtcEvent_SessionClosedAckImplCopyWith<$Res> {
  __$$WebRtcEvent_SessionClosedAckImplCopyWithImpl(
    _$WebRtcEvent_SessionClosedAckImpl _value,
    $Res Function(_$WebRtcEvent_SessionClosedAckImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? id = freezed}) {
    return _then(
      _$WebRtcEvent_SessionClosedAckImpl(
        id: freezed == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_SessionClosedAckImpl extends WebRtcEvent_SessionClosedAck {
  const _$WebRtcEvent_SessionClosedAckImpl({this.id}) : super._();

  @override
  final String? id;

  @override
  String toString() {
    return 'WebRtcEvent.sessionClosedAck(id: $id)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_SessionClosedAckImpl &&
            (identical(other.id, id) || other.id == id));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_SessionClosedAckImplCopyWith<
    _$WebRtcEvent_SessionClosedAckImpl
  >
  get copyWith =>
      __$$WebRtcEvent_SessionClosedAckImplCopyWithImpl<
        _$WebRtcEvent_SessionClosedAckImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return sessionClosedAck(id);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return sessionClosedAck?.call(id);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (sessionClosedAck != null) {
      return sessionClosedAck(id);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return sessionClosedAck(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return sessionClosedAck?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (sessionClosedAck != null) {
      return sessionClosedAck(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_SessionClosedAck extends WebRtcEvent {
  const factory WebRtcEvent_SessionClosedAck({final String? id}) =
      _$WebRtcEvent_SessionClosedAckImpl;
  const WebRtcEvent_SessionClosedAck._() : super._();

  String? get id;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_SessionClosedAckImplCopyWith<
    _$WebRtcEvent_SessionClosedAckImpl
  >
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_PingImplCopyWith<$Res> {
  factory _$$WebRtcEvent_PingImplCopyWith(
    _$WebRtcEvent_PingImpl value,
    $Res Function(_$WebRtcEvent_PingImpl) then,
  ) = __$$WebRtcEvent_PingImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String? ts});
}

/// @nodoc
class __$$WebRtcEvent_PingImplCopyWithImpl<$Res>
    extends _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_PingImpl>
    implements _$$WebRtcEvent_PingImplCopyWith<$Res> {
  __$$WebRtcEvent_PingImplCopyWithImpl(
    _$WebRtcEvent_PingImpl _value,
    $Res Function(_$WebRtcEvent_PingImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? ts = freezed}) {
    return _then(
      _$WebRtcEvent_PingImpl(
        ts: freezed == ts
            ? _value.ts
            : ts // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_PingImpl extends WebRtcEvent_Ping {
  const _$WebRtcEvent_PingImpl({this.ts}) : super._();

  @override
  final String? ts;

  @override
  String toString() {
    return 'WebRtcEvent.ping(ts: $ts)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_PingImpl &&
            (identical(other.ts, ts) || other.ts == ts));
  }

  @override
  int get hashCode => Object.hash(runtimeType, ts);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_PingImplCopyWith<_$WebRtcEvent_PingImpl> get copyWith =>
      __$$WebRtcEvent_PingImplCopyWithImpl<_$WebRtcEvent_PingImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return ping(ts);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return ping?.call(ts);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (ping != null) {
      return ping(ts);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return ping(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return ping?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (ping != null) {
      return ping(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_Ping extends WebRtcEvent {
  const factory WebRtcEvent_Ping({final String? ts}) = _$WebRtcEvent_PingImpl;
  const WebRtcEvent_Ping._() : super._();

  String? get ts;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_PingImplCopyWith<_$WebRtcEvent_PingImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_PongImplCopyWith<$Res> {
  factory _$$WebRtcEvent_PongImplCopyWith(
    _$WebRtcEvent_PongImpl value,
    $Res Function(_$WebRtcEvent_PongImpl) then,
  ) = __$$WebRtcEvent_PongImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String? ts});
}

/// @nodoc
class __$$WebRtcEvent_PongImplCopyWithImpl<$Res>
    extends _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_PongImpl>
    implements _$$WebRtcEvent_PongImplCopyWith<$Res> {
  __$$WebRtcEvent_PongImplCopyWithImpl(
    _$WebRtcEvent_PongImpl _value,
    $Res Function(_$WebRtcEvent_PongImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? ts = freezed}) {
    return _then(
      _$WebRtcEvent_PongImpl(
        ts: freezed == ts
            ? _value.ts
            : ts // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_PongImpl extends WebRtcEvent_Pong {
  const _$WebRtcEvent_PongImpl({this.ts}) : super._();

  @override
  final String? ts;

  @override
  String toString() {
    return 'WebRtcEvent.pong(ts: $ts)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_PongImpl &&
            (identical(other.ts, ts) || other.ts == ts));
  }

  @override
  int get hashCode => Object.hash(runtimeType, ts);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_PongImplCopyWith<_$WebRtcEvent_PongImpl> get copyWith =>
      __$$WebRtcEvent_PongImplCopyWithImpl<_$WebRtcEvent_PongImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return pong(ts);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return pong?.call(ts);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (pong != null) {
      return pong(ts);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return pong(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return pong?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (pong != null) {
      return pong(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_Pong extends WebRtcEvent {
  const factory WebRtcEvent_Pong({final String? ts}) = _$WebRtcEvent_PongImpl;
  const WebRtcEvent_Pong._() : super._();

  String? get ts;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_PongImplCopyWith<_$WebRtcEvent_PongImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_ControlMessageImplCopyWith<$Res> {
  factory _$$WebRtcEvent_ControlMessageImplCopyWith(
    _$WebRtcEvent_ControlMessageImpl value,
    $Res Function(_$WebRtcEvent_ControlMessageImpl) then,
  ) = __$$WebRtcEvent_ControlMessageImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$WebRtcEvent_ControlMessageImplCopyWithImpl<$Res>
    extends _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_ControlMessageImpl>
    implements _$$WebRtcEvent_ControlMessageImplCopyWith<$Res> {
  __$$WebRtcEvent_ControlMessageImplCopyWithImpl(
    _$WebRtcEvent_ControlMessageImpl _value,
    $Res Function(_$WebRtcEvent_ControlMessageImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = null}) {
    return _then(
      _$WebRtcEvent_ControlMessageImpl(
        message: null == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_ControlMessageImpl extends WebRtcEvent_ControlMessage {
  const _$WebRtcEvent_ControlMessageImpl({required this.message}) : super._();

  @override
  final String message;

  @override
  String toString() {
    return 'WebRtcEvent.controlMessage(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_ControlMessageImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_ControlMessageImplCopyWith<_$WebRtcEvent_ControlMessageImpl>
  get copyWith =>
      __$$WebRtcEvent_ControlMessageImplCopyWithImpl<
        _$WebRtcEvent_ControlMessageImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return controlMessage(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return controlMessage?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (controlMessage != null) {
      return controlMessage(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return controlMessage(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return controlMessage?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (controlMessage != null) {
      return controlMessage(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_ControlMessage extends WebRtcEvent {
  const factory WebRtcEvent_ControlMessage({required final String message}) =
      _$WebRtcEvent_ControlMessageImpl;
  const WebRtcEvent_ControlMessage._() : super._();

  String get message;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_ControlMessageImplCopyWith<_$WebRtcEvent_ControlMessageImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_FileMessageImplCopyWith<$Res> {
  factory _$$WebRtcEvent_FileMessageImplCopyWith(
    _$WebRtcEvent_FileMessageImpl value,
    $Res Function(_$WebRtcEvent_FileMessageImpl) then,
  ) = __$$WebRtcEvent_FileMessageImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$WebRtcEvent_FileMessageImplCopyWithImpl<$Res>
    extends _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_FileMessageImpl>
    implements _$$WebRtcEvent_FileMessageImplCopyWith<$Res> {
  __$$WebRtcEvent_FileMessageImplCopyWithImpl(
    _$WebRtcEvent_FileMessageImpl _value,
    $Res Function(_$WebRtcEvent_FileMessageImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = null}) {
    return _then(
      _$WebRtcEvent_FileMessageImpl(
        message: null == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_FileMessageImpl extends WebRtcEvent_FileMessage {
  const _$WebRtcEvent_FileMessageImpl({required this.message}) : super._();

  @override
  final String message;

  @override
  String toString() {
    return 'WebRtcEvent.fileMessage(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_FileMessageImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_FileMessageImplCopyWith<_$WebRtcEvent_FileMessageImpl>
  get copyWith =>
      __$$WebRtcEvent_FileMessageImplCopyWithImpl<
        _$WebRtcEvent_FileMessageImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return fileMessage(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return fileMessage?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (fileMessage != null) {
      return fileMessage(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return fileMessage(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return fileMessage?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (fileMessage != null) {
      return fileMessage(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_FileMessage extends WebRtcEvent {
  const factory WebRtcEvent_FileMessage({required final String message}) =
      _$WebRtcEvent_FileMessageImpl;
  const WebRtcEvent_FileMessage._() : super._();

  String get message;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_FileMessageImplCopyWith<_$WebRtcEvent_FileMessageImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_FileChunkImplCopyWith<$Res> {
  factory _$$WebRtcEvent_FileChunkImplCopyWith(
    _$WebRtcEvent_FileChunkImpl value,
    $Res Function(_$WebRtcEvent_FileChunkImpl) then,
  ) = __$$WebRtcEvent_FileChunkImplCopyWithImpl<$Res>;
  @useResult
  $Res call({Uint8List bytes});
}

/// @nodoc
class __$$WebRtcEvent_FileChunkImplCopyWithImpl<$Res>
    extends _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_FileChunkImpl>
    implements _$$WebRtcEvent_FileChunkImplCopyWith<$Res> {
  __$$WebRtcEvent_FileChunkImplCopyWithImpl(
    _$WebRtcEvent_FileChunkImpl _value,
    $Res Function(_$WebRtcEvent_FileChunkImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? bytes = null}) {
    return _then(
      _$WebRtcEvent_FileChunkImpl(
        bytes: null == bytes
            ? _value.bytes
            : bytes // ignore: cast_nullable_to_non_nullable
                  as Uint8List,
      ),
    );
  }
}

/// @nodoc

class _$WebRtcEvent_FileChunkImpl extends WebRtcEvent_FileChunk {
  const _$WebRtcEvent_FileChunkImpl({required this.bytes}) : super._();

  @override
  final Uint8List bytes;

  @override
  String toString() {
    return 'WebRtcEvent.fileChunk(bytes: $bytes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_FileChunkImpl &&
            const DeepCollectionEquality().equals(other.bytes, bytes));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(bytes));

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WebRtcEvent_FileChunkImplCopyWith<_$WebRtcEvent_FileChunkImpl>
  get copyWith =>
      __$$WebRtcEvent_FileChunkImplCopyWithImpl<_$WebRtcEvent_FileChunkImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return fileChunk(bytes);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return fileChunk?.call(bytes);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (fileChunk != null) {
      return fileChunk(bytes);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return fileChunk(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return fileChunk?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (fileChunk != null) {
      return fileChunk(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_FileChunk extends WebRtcEvent {
  const factory WebRtcEvent_FileChunk({required final Uint8List bytes}) =
      _$WebRtcEvent_FileChunkImpl;
  const WebRtcEvent_FileChunk._() : super._();

  Uint8List get bytes;

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WebRtcEvent_FileChunkImplCopyWith<_$WebRtcEvent_FileChunkImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$WebRtcEvent_FileBufferedAmountLowImplCopyWith<$Res> {
  factory _$$WebRtcEvent_FileBufferedAmountLowImplCopyWith(
    _$WebRtcEvent_FileBufferedAmountLowImpl value,
    $Res Function(_$WebRtcEvent_FileBufferedAmountLowImpl) then,
  ) = __$$WebRtcEvent_FileBufferedAmountLowImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$WebRtcEvent_FileBufferedAmountLowImplCopyWithImpl<$Res>
    extends
        _$WebRtcEventCopyWithImpl<$Res, _$WebRtcEvent_FileBufferedAmountLowImpl>
    implements _$$WebRtcEvent_FileBufferedAmountLowImplCopyWith<$Res> {
  __$$WebRtcEvent_FileBufferedAmountLowImplCopyWithImpl(
    _$WebRtcEvent_FileBufferedAmountLowImpl _value,
    $Res Function(_$WebRtcEvent_FileBufferedAmountLowImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WebRtcEvent
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$WebRtcEvent_FileBufferedAmountLowImpl
    extends WebRtcEvent_FileBufferedAmountLow {
  const _$WebRtcEvent_FileBufferedAmountLowImpl() : super._();

  @override
  String toString() {
    return 'WebRtcEvent.fileBufferedAmountLow()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WebRtcEvent_FileBufferedAmountLowImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String state) connectionStateChanged,
    required TResult Function(String label, String state)
    dataChannelStateChanged,
    required TResult Function(IceCandidateDto candidate) localIceCandidate,
    required TResult Function(SessionDescriptionDto description)
    renegotiationOffer,
    required TResult Function(SessionDescriptionDto description)
    renegotiationAnswer,
    required TResult Function(IceCandidateDto candidate) renegotiationIce,
    required TResult Function() screenShareStopped,
    required TResult Function() fileTransferRequested,
    required TResult Function(String? id, String? reason) sessionClosed,
    required TResult Function(String? id) sessionClosedAck,
    required TResult Function(String? ts) ping,
    required TResult Function(String? ts) pong,
    required TResult Function(String message) controlMessage,
    required TResult Function(String message) fileMessage,
    required TResult Function(Uint8List bytes) fileChunk,
    required TResult Function() fileBufferedAmountLow,
  }) {
    return fileBufferedAmountLow();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String state)? connectionStateChanged,
    TResult? Function(String label, String state)? dataChannelStateChanged,
    TResult? Function(IceCandidateDto candidate)? localIceCandidate,
    TResult? Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult? Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult? Function(IceCandidateDto candidate)? renegotiationIce,
    TResult? Function()? screenShareStopped,
    TResult? Function()? fileTransferRequested,
    TResult? Function(String? id, String? reason)? sessionClosed,
    TResult? Function(String? id)? sessionClosedAck,
    TResult? Function(String? ts)? ping,
    TResult? Function(String? ts)? pong,
    TResult? Function(String message)? controlMessage,
    TResult? Function(String message)? fileMessage,
    TResult? Function(Uint8List bytes)? fileChunk,
    TResult? Function()? fileBufferedAmountLow,
  }) {
    return fileBufferedAmountLow?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String state)? connectionStateChanged,
    TResult Function(String label, String state)? dataChannelStateChanged,
    TResult Function(IceCandidateDto candidate)? localIceCandidate,
    TResult Function(SessionDescriptionDto description)? renegotiationOffer,
    TResult Function(SessionDescriptionDto description)? renegotiationAnswer,
    TResult Function(IceCandidateDto candidate)? renegotiationIce,
    TResult Function()? screenShareStopped,
    TResult Function()? fileTransferRequested,
    TResult Function(String? id, String? reason)? sessionClosed,
    TResult Function(String? id)? sessionClosedAck,
    TResult Function(String? ts)? ping,
    TResult Function(String? ts)? pong,
    TResult Function(String message)? controlMessage,
    TResult Function(String message)? fileMessage,
    TResult Function(Uint8List bytes)? fileChunk,
    TResult Function()? fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (fileBufferedAmountLow != null) {
      return fileBufferedAmountLow();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(WebRtcEvent_ConnectionStateChanged value)
    connectionStateChanged,
    required TResult Function(WebRtcEvent_DataChannelStateChanged value)
    dataChannelStateChanged,
    required TResult Function(WebRtcEvent_LocalIceCandidate value)
    localIceCandidate,
    required TResult Function(WebRtcEvent_RenegotiationOffer value)
    renegotiationOffer,
    required TResult Function(WebRtcEvent_RenegotiationAnswer value)
    renegotiationAnswer,
    required TResult Function(WebRtcEvent_RenegotiationIce value)
    renegotiationIce,
    required TResult Function(WebRtcEvent_ScreenShareStopped value)
    screenShareStopped,
    required TResult Function(WebRtcEvent_FileTransferRequested value)
    fileTransferRequested,
    required TResult Function(WebRtcEvent_SessionClosed value) sessionClosed,
    required TResult Function(WebRtcEvent_SessionClosedAck value)
    sessionClosedAck,
    required TResult Function(WebRtcEvent_Ping value) ping,
    required TResult Function(WebRtcEvent_Pong value) pong,
    required TResult Function(WebRtcEvent_ControlMessage value) controlMessage,
    required TResult Function(WebRtcEvent_FileMessage value) fileMessage,
    required TResult Function(WebRtcEvent_FileChunk value) fileChunk,
    required TResult Function(WebRtcEvent_FileBufferedAmountLow value)
    fileBufferedAmountLow,
  }) {
    return fileBufferedAmountLow(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult? Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult? Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult? Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult? Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult? Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult? Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult? Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult? Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult? Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult? Function(WebRtcEvent_Ping value)? ping,
    TResult? Function(WebRtcEvent_Pong value)? pong,
    TResult? Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult? Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult? Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult? Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
  }) {
    return fileBufferedAmountLow?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(WebRtcEvent_ConnectionStateChanged value)?
    connectionStateChanged,
    TResult Function(WebRtcEvent_DataChannelStateChanged value)?
    dataChannelStateChanged,
    TResult Function(WebRtcEvent_LocalIceCandidate value)? localIceCandidate,
    TResult Function(WebRtcEvent_RenegotiationOffer value)? renegotiationOffer,
    TResult Function(WebRtcEvent_RenegotiationAnswer value)?
    renegotiationAnswer,
    TResult Function(WebRtcEvent_RenegotiationIce value)? renegotiationIce,
    TResult Function(WebRtcEvent_ScreenShareStopped value)? screenShareStopped,
    TResult Function(WebRtcEvent_FileTransferRequested value)?
    fileTransferRequested,
    TResult Function(WebRtcEvent_SessionClosed value)? sessionClosed,
    TResult Function(WebRtcEvent_SessionClosedAck value)? sessionClosedAck,
    TResult Function(WebRtcEvent_Ping value)? ping,
    TResult Function(WebRtcEvent_Pong value)? pong,
    TResult Function(WebRtcEvent_ControlMessage value)? controlMessage,
    TResult Function(WebRtcEvent_FileMessage value)? fileMessage,
    TResult Function(WebRtcEvent_FileChunk value)? fileChunk,
    TResult Function(WebRtcEvent_FileBufferedAmountLow value)?
    fileBufferedAmountLow,
    required TResult orElse(),
  }) {
    if (fileBufferedAmountLow != null) {
      return fileBufferedAmountLow(this);
    }
    return orElse();
  }
}

abstract class WebRtcEvent_FileBufferedAmountLow extends WebRtcEvent {
  const factory WebRtcEvent_FileBufferedAmountLow() =
      _$WebRtcEvent_FileBufferedAmountLowImpl;
  const WebRtcEvent_FileBufferedAmountLow._() : super._();
}
