import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/reading_preferences.dart';
import '../../../core/theme/appearance_settings.dart';
import '../../study/domain/providers.dart';

class ReadingPage extends ConsumerStatefulWidget {
  const ReadingPage({super.key});
  @override ConsumerState<ReadingPage> createState()=>_ReadingPageState();
}
class _ReadingPageState extends ConsumerState<ReadingPage> {
  final _values=<String,double>{'word_size':32,'meaning_size':24,'line_height':1.4,'speech_rate':.45,
    'background_blur':0,'background_opacity':.72,'background_x':0,'background_y':0,'background_zoom':1};
  bool _focus=false,_ready=false;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{
    final db=ref.read(databaseProvider);
    for(final key in _values.keys.toList()){ _values[key]=double.tryParse(await db.loadSetting(key)??'')??_values[key]!; }
    _focus=await db.loadSetting('focus_mode')=='true';
    if(mounted)setState(()=>_ready=true);
  }
  Future<void> _save(String key,double value)async{
    await ref.read(databaseProvider).saveSetting(key,'$value');
    ref.invalidate(readingProvider);ref.invalidate(appearanceProvider);
  }
  Widget _slider(String key,String label,double min,double max)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('$label · ${_values[key]!.toStringAsFixed(2)}'),Slider(value:_values[key]!.clamp(min,max),min:min,max:max,
      onChanged:(v)=>setState(()=>_values[key]=v),onChangeEnd:(v)=>_save(key,v)),
  ]);
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('阅读与背景')),body:!_ready?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(22),children:[
    Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[
      Text('안녕하세요',style:TextStyle(fontSize:_values['word_size'],height:_values['line_height'])),
      Text('每天让记忆更清晰',style:TextStyle(fontSize:_values['meaning_size'],height:_values['line_height'])),
    ]))),const SizedBox(height:18),
    _slider('word_size','单词字号',24,48),_slider('meaning_size','释义字号',18,32),
    _slider('line_height','行距',1.1,2),_slider('speech_rate','发音速度',.2,.8),
    SwitchListTile(title:const Text('专注学习模式'),subtitle:const Text('学习页收起底部导航，顶部仍可返回首页'),value:_focus,onChanged:(v)async{
      setState(()=>_focus=v);await ref.read(databaseProvider).saveSetting('focus_mode','$v');ref.invalidate(readingProvider);
    }),const Divider(),Text('背景图片调整',style:Theme.of(context).textTheme.titleLarge),
    const Text('在“外观风格”中上传图片后生效。缩放与位置调整可裁掉多余画面。'),
    _slider('background_blur','模糊程度',0,12),_slider('background_opacity','阅读遮罩强度',.2,.9),
    _slider('background_zoom','图片缩放',1,2),_slider('background_x','水平位置',-1,1),_slider('background_y','垂直位置',-1,1),
  ]));
}
