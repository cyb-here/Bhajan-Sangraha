import 'dart:io';
void main(){
  final f=File('lib/config.dart');
  if(!f.existsSync()){print('config file missing'); exit(1);} 
  final c=f.readAsStringSync();
  print('----BEGIN CONFIG----');
  print(c);
  print('----END CONFIG----');
  final u=RegExp(r"SUPABASE_URL\s*=\s*'([^']*)'");
  final k=RegExp(r"SUPABASE_ANON_KEY\s*=\s*'([^']*)'");
  final um=u.firstMatch(c);
  final km=k.firstMatch(c);
  print('URL match: ${um!=null}');
  if(um!=null) print('URL=${um!.group(1)}');
  print('KEY match: ${km!=null}');
  if(km!=null) print('KEY=${km!.group(1)}');
}
