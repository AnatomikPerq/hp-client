import 'package:onexray/core/tools/logger.dart';

/// Documentation lives in the fork's repository: the upstream site describes
/// another product, and its privacy policy does not apply to this App.
class DocURLHelper {
  static const _repository = 'https://github.com/AnatomikPerq/hp-client';

  static Uri _log(Uri uri) {
    ygLogger('$uri');
    return uri;
  }

  static Uri docUri() => _log(Uri.parse('$_repository#readme'));

  static Uri creditsUri() =>
      _log(Uri.parse('$_repository/blob/main/LICENSE-THIRD-PARTY.md'));

  static Uri privacyUri() =>
      _log(Uri.parse('$_repository/blob/main/PRIVACY.md'));
}
