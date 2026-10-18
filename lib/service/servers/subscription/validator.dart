import 'package:onexray/core/network/client.dart';
import 'package:onexray/service/servers/subscription/model.dart';

abstract final class SubscriptionValidator {
  /// [allowEmptyName]: a new subscription may leave the name to the
  /// provider's `Profile-Title`, or the host.
  static SubscriptionUpdateResult? validate(
    SubscriptionInput input, {
    bool allowEmptyName = false,
  }) {
    if (input.name.trim().isEmpty && !allowEmptyName) {
      return SubscriptionUpdateResult.nameRequired;
    }
    if (input.url.isEmpty) return SubscriptionUpdateResult.urlRequired;
    final uri = Uri.tryParse(input.url);
    if (uri == null || !NetClient.isHttpsDownloadUri(uri)) {
      return SubscriptionUpdateResult.urlInvalid;
    }
    if (input.hasIncompleteAgeKeyPair) {
      return SubscriptionUpdateResult.incompleteAgeKeys;
    }
    return null;
  }
}
