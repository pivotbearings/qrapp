import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient();
  const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN1YXN4ZWh1dWFka2FwZWhheGtoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE1NjM0NDQsImV4cCI6MjEwNzEzOTQ0NH0.T60jcH4gy1cGnSqM7Qrv1dyebPQ0KllaGl3xGYKZ_H0';
  
  // 1. Sign in to Supabase
  final authUrl = Uri.parse('https://cuasxehuuadkapehaxkh.supabase.co/auth/v1/token?grant_type=password');
  final authReq = await client.postUrl(authUrl);
  authReq.headers.set('apikey', anonKey);
  authReq.headers.set('Content-Type', 'application/json');
  authReq.add(utf8.encode(jsonEncode({
    'email': 'test_dev_1@gmail.com',
    'password': 'Password123!',
  })));
  final authRes = await authReq.close();
  final authBody = await authRes.transform(utf8.decoder).join();
  final authData = jsonDecode(authBody);
  final token = authData['access_token'] ?? anonKey;
  print('AUTH STATUS: ${authRes.statusCode}');

  // 2. Query qr_codes for juVjDjzKJwY2
  final url = Uri.parse('https://cuasxehuuadkapehaxkh.supabase.co/rest/v1/qr_codes?select=*,qr_batches(*),warranty_plans:assigned_warranty_plan_id(*)');
  final req = await client.getUrl(url);
  req.headers.set('apikey', anonKey);
  req.headers.set('Authorization', 'Bearer $token');
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  print('QR_CODES STATUS: ${res.statusCode}');
  print('QR_CODES COUNT: ${(jsonDecode(body) as List).length}');
  final list = jsonDecode(body) as List;
  for (final item in list) {
    if (item['bearing_id'].toString().contains('juV') || item['bearing_id'].toString().contains('JUV')) {
      print('FOUND juVjDjzKJwY2: ${jsonEncode(item)}');
    }
    if (item['bearing_id'].toString().contains('HWM') || item['bearing_id'].toString().contains('hwm')) {
      print('FOUND HWM: ${jsonEncode(item)}');
    }
  }

  // 3. Query all warranty plans
  final planUrl = Uri.parse('https://cuasxehuuadkapehaxkh.supabase.co/rest/v1/warranty_plans?select=*');
  final planReq = await client.getUrl(planUrl);
  planReq.headers.set('apikey', anonKey);
  planReq.headers.set('Authorization', 'Bearer $token');
  final planRes = await planReq.close();
  final planBody = await planRes.transform(utf8.decoder).join();
  print('WARRANTY PLANS: $planBody');

  // 4. Query verify_bearing_qr RPC for juVjDjzKJwY2
  final rpcUrl = Uri.parse('https://cuasxehuuadkapehaxkh.supabase.co/rest/v1/rpc/verify_bearing_qr');
  final rpcReq = await client.postUrl(rpcUrl);
  rpcReq.headers.set('apikey', anonKey);
  rpcReq.headers.set('Authorization', 'Bearer $token');
  rpcReq.headers.set('Content-Type', 'application/json');
  rpcReq.add(utf8.encode(jsonEncode({'p_scanned_payload': 'juVjDjzKJwY2'})));
  final rpcRes = await rpcReq.close();
  final rpcBody = await rpcRes.transform(utf8.decoder).join();
  print('RPC verify_bearing_qr STATUS: ${rpcRes.statusCode}');
  print('RPC verify_bearing_qr BODY: $rpcBody');
}
