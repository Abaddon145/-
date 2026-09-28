import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../library/presentation/library_page.dart';
import '../../statistics/presentation/statistics_page.dart';
import '../../study/domain/providers.dart';
import '../../study/presentation/study_controller.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState()=>_SettingsPageState();
}
class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy=false;
  Future<void> _backup() async {
    setState(()=>_busy=true);
    try {
      final data=await ref.read(databaseProvider).createBackupSnapshot();
      final bytes=Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
      final saved=await FilePicker.saveFile(fileName:'korean-memo-backup.json',bytes:bytes,mimeType:'application/json');
      if(saved!=null&&mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('备份文件已导出')));
    } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('备份失败：$e'))); }
    finally { if(mounted)setState(()=>_busy=false); }
  }
  Future<void> _restore() async {
    try {
      final file=await FilePicker.pickFile(type:FileType.custom,allowedExtensions:const ['json']);
      if(file==null)return;
      final bytes=await file.readAsBytes();
      if(bytes.isEmpty||bytes.length>20*1024*1024) throw const FormatException('备份文件为空或超过 20 MB');
      final decoded=jsonDecode(utf8.decode(bytes));
      if(decoded is! Map<String,dynamic>) throw const FormatException('备份文件格式无效');
      if(!mounted)return;
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('恢复备份？'),
        content:const Text('恢复会替换此设备上的整个词库、学习进度和设置。建议先导出当前备份。'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('取消')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('替换并恢复'))]));
      if(ok!=true)return;
      setState(()=>_busy=true);
      await ref.read(databaseProvider).restoreBackupSnapshot(decoded);
      ref.invalidate(homeCountsProvider);ref.invalidate(studyControllerProvider);ref.invalidate(dailyPlanProgressProvider);
      ref.invalidate(libraryWordsProvider);ref.invalidate(recentStatisticsProvider);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('学习进度已恢复')));
    } catch(e) { if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('恢复失败：$e'))); }
    finally { if(mounted)setState(()=>_busy=false); }
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('设置')),body:ListView(children:[
    ListTile(leading:const Icon(Icons.today_outlined),title:const Text('每日学习计划'),subtitle:const Text('设置每日新词数量和复习上限'),trailing:const Icon(Icons.chevron_right),onTap:()=>context.push('/settings/daily-plan')),
    const Divider(),
    ListTile(leading:const Icon(Icons.download_outlined),title:const Text('备份学习进度'),subtitle:const Text('导出词库、学习记录和设置为 JSON 文件'),onTap:_busy?null:_backup),
    ListTile(leading:const Icon(Icons.restore),title:const Text('恢复学习进度'),subtitle:const Text('从 JSON 备份替换本机数据'),onTap:_busy?null:_restore),
    if(_busy) const LinearProgressIndicator(),
  ]));
}
