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

  final urlCycles = Uri.parse('https://cuasxehuuadkapehaxkh.supabase.co/rest/v1/bearing_installation_cycles?select=*');
  final reqCycles = await client.getUrl(urlCycles);
  reqCycles.headers.set('apikey', anonKey);
  reqCycles.headers.set('Authorization', 'Bearer $token');
  final resCycles = await reqCycles.close();
  final bodyCycles = await resCycles.transform(utf8.decoder).join();
  print('ALL CYCLES COUNT: ${(jsonDecode(bodyCycles) as List).length}');
  print('ALL CYCLES: $bodyCycles');
}
