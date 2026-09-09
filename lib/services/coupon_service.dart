import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/database.dart';
import 'catalog_sync_service.dart';

/// Un cupón de descuento de la tienda: porcentaje o monto fijo.
class Coupon {
  Coupon({
    required this.code,
    required this.kind,
    required this.value,
    required this.active,
  });

  final String code;

  /// 'percent' (value = 1..100) o 'fixed' (value = centavos).
  final String kind;
  final int value;
  final bool active;

  bool get isPercent => kind == 'percent';

  factory Coupon.fromJson(Map<String, dynamic> j) => Coupon(
        code: j['code'] as String? ?? '',
        kind: j['kind'] as String? ?? 'percent',
        value: (j['value'] as num?)?.toInt() ?? 0,
        active: j['active'] as bool? ?? true,
      );
}

/// Gestiona los cupones en Supabase reusando el secreto de publicación y la
/// conexión que ya usa el catálogo (`CatalogSyncService`) — sin credencial
/// nueva. La validación real del descuento la hace el servidor al cobrar
/// (`process-payment`); esto es solo la administración desde el POS.
class CouponService {
  CouponService(this._db);
  final AppDatabase _db;
  late final CatalogSyncService _sync = CatalogSyncService(_db);
  SupabaseClient get _client => Supabase.instance.client;

  bool get available => _sync.available;

  Future<List<Coupon>> list() async {
    final secret = await _sync.ensureSecret();
    final res = await _client.rpc('list_coupons', params: {'p_secret': secret});
    final rows = (res as List?) ?? [];
    return rows
        .map((e) => Coupon.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> upsert({
    required String code,
    required String kind,
    required int value,
    required bool active,
  }) async {
    final secret = await _sync.ensureSecret();
    await _client.rpc('upsert_coupon', params: {
      'p_secret': secret,
      'p_code': code,
      'p_kind': kind,
      'p_value': value,
      'p_active': active,
    });
  }

  Future<void> delete(String code) async {
    final secret = await _sync.ensureSecret();
    await _client
        .rpc('delete_coupon', params: {'p_secret': secret, 'p_code': code});
  }
}
