import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:tuple/tuple.dart';

class SubscriptionValidator {
  /// [allowEmptyName]: a new subscription may leave the name to the
  /// provider's `Profile-Title`, or the host.
  static Future<Tuple2<bool, String>> validate(
    String name,
    String url, {
    int? excludingId,
    bool allowEmptyName = false,
  }) async {
    if (name.isEmpty && !allowEmptyName) {
      return Tuple2(false, appLocalizationsNoContext().validationNameRequired);
    }
    if (url.isEmpty) {
      return Tuple2(false, appLocalizationsNoContext().validationUrlRequired);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !NetClient.isHttpsDownloadUri(uri)) {
      return Tuple2(false, appLocalizationsNoContext().validationUrlInvalid);
    }
    final db = AppDatabase();
    final urlExists = await db.subscriptionDao.urlExists(
      url,
      excludingId: excludingId,
    );
    if (urlExists) {
      return Tuple2(false, appLocalizationsNoContext().validationUrlDuplicate);
    }
    return Tuple2(true, "");
  }
}
