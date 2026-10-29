import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient();
  const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN1YXN4ZWh1dWFka2FwZWhheGtoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE1NjM0NDQsImV4cCI6MjEwNzEzOTQ0NH0.T60jcH4gy1cGnSqM7Qrv1dyebPQ0KllaGl3xGYKZ_H0';
  
  final authUrl = Uri.parse('https://cuasxehuuadkapehaxkh.supabase.co/auth/v1/token?grant_type=password');
  final authReq = await client.postUrl(authUrl);
  authReq.headers.set('apikey', anonKey);
  authReq.headers.set('Content-Type', 'application/json');
  authReq.add(utf8.encode(jsonEncode({
    'email': 'test_dev_1@gmail.com',
    'password': 'Password123!',
  })));
  final authRes = await authReq.close();
  final authData = jsonDecode(await authRes.transform(utf8.decoder).join());
  final token = authData['access_token'] ?? anonKey;

  // Test calling confirm_bearing_in RPC
  final rpcInUrl = Uri.parse('https://cuasxehuuadkapehaxkh.supabase.co/rest/v1/rpc/confirm_bearing_in');
  final rpcReq = await client.postUrl(rpcInUrl);
  rpcReq.headers.set('apikey', anonKey);
  rpcReq.headers.set('Authorization', 'Bearer $token');
  rpcReq.headers.set('Content-Type', 'application/json');
  rpcReq.add(utf8.encode(jsonEncode({
    'p_bearing_id': 'juVjDjzKJwY2',
    'p_verification_image_id': null,
    'p_notes': 'test call',
  })));
  final rpcRes = await rpcReq.close();
  final rpcBody = await rpcRes.transform(utf8.decoder).join();
  print('confirm_bearing_in STATUS: ${rpcRes.statusCode}');
  print('confirm_bearing_in BODY: $rpcBody');
}

