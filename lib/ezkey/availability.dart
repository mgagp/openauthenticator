import 'package:open_authenticator/utils/platform.dart';

/// The platforms where EzKey is offered (docs/adr/0004-ezkey-multi-platform-posture.md).
///
/// A platform joins only once it has a hardware key store behind the `ezkey_keystore` channel, a way
/// to enroll in release builds, and a build that was checked. Elsewhere the app stays exactly as
/// upstream.
const Set<Platform> ezkeySupportedPlatforms = {Platform.android};

/// Whether EzKey is offered on the current platform. Every EzKey entry point checks it.
bool get ezkeyAvailable => ezkeySupportedPlatforms.contains(currentPlatform);

/// Whether an invitation's QR code can be scanned on the current platform: where upstream's scanner
/// (`mobile_scanner`) has an implementation. Elsewhere, pasting the invitation is the only way to enroll.
bool get ezkeyCanScan => const {Platform.android, Platform.iOS, Platform.macOS}.contains(currentPlatform);
