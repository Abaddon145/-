import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';

final librarySearchProvider = StateProvider.autoDispose<String>((ref) => '');
final libraryFilterProvider = StateProvider.autoDispose<LibraryFilter>((ref) => LibraryFilter.all);
final libraryWordsProvider = FutureProvider.autoDispose<List<LibraryWordEntry>>((ref) {
  return ref.watch(databaseProvider).searchLibraryWords(query: ref.watch(librarySearchProvider), filter: ref.watch(libraryFilterProvider));
});

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(libraryWordsProvider);
    final filter = ref.watch(libraryFilterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('词库'), actions: [IconButton(tooltip:'导入词库',icon:const Icon(Icons.file_upload_outlined),onPressed:()=>context.push('/import'))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: TextField(
          onChanged: (value) => ref.read(librarySearchProvider.notifier).state = value,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索韩语或中文', border: OutlineInputBorder()),
        )),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for(final entry in [(LibraryFilter.all,'全部'),(LibraryFilter.favorites,'收藏'),(LibraryFilter.wrong,'错词本')])
            Padding(padding: const EdgeInsets.symmetric(horizontal:4),child: ChoiceChip(label:Text(entry.$2),selected:filter==entry.$1,onSelected:(_)=>ref.read(libraryFilterProvider.notifier).state=entry.$1))
        ])),
        Expanded(child: words.when(
          loading:()=>const Center(child:CircularProgressIndicator()),
          error:(e,_)=>Center(child:Text('读取词库失败：$e')),
          data:(items)=>items.isEmpty?const Center(child:Text('没有找到词条')):ListView.builder(
            itemCount:items.length,itemBuilder:(context,index){
              final item=items[index];
              return ListTile(
                title:Text(item.word.korean),subtitle:Text(item.word.meaningZh),
                trailing:Row(mainAxisSize:MainAxisSize.min,children:[
                  if(item.wrongCount>0) const Icon(Icons.error_outline,color:Colors.deepOrange,size:20),
                  IconButton(tooltip:item.isFavorite?'取消收藏':'收藏',icon:Icon(item.isFavorite?Icons.star:Icons.star_border,color:item.isFavorite?Colors.amber:null),
                    onPressed:()async{await ref.read(databaseProvider).setFavorite(item.word.id,!item.isFavorite);ref.invalidate(libraryWordsProvider);}),
                  PopupMenuButton<String>(onSelected:(action)async{
                    if(action=='edit'){
                      final korean=TextEditingController(text:item.word.korean), meaning=TextEditingController(text:item.word.meaningZh);
                      final form=GlobalKey<FormState>();
                      final changed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('编辑词条'),content:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
                        TextFormField(controller:korean,decoration:const InputDecoration(labelText:'韩语'),validator:(v)=>v==null||v.trim().isEmpty?'不能为空':null),
                        TextFormField(controller:meaning,decoration:const InputDecoration(labelText:'中文释义'),validator:(v)=>v==null||v.trim().isEmpty?'不能为空':null),
                      ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('取消')),FilledButton(onPressed:()=>form.currentState!.validate()?Navigator.pop(ctx,true):null,child:const Text('保存'))]));
                      if(changed==true){await ref.read(databaseProvider).updateWord(wordId:item.word.id,korean:korean.text,meaningZh:meaning.text);ref.invalidate(libraryWordsProvider);}
                    }else{
                      final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('删除词条？'),content:const Text('删除后会同时移除该词的复习记录和学习状态，此操作无法撤销。'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('取消')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('删除'))]));
                      if(confirmed==true){await ref.read(databaseProvider).deleteWord(item.word.id);ref.invalidate(libraryWordsProvider);}
                    }
                  },itemBuilder:(_)=>const [PopupMenuItem(value:'edit',child:Text('编辑')),PopupMenuItem(value:'delete',child:Text('删除'))])
                ]),
              );
            })))
      ]),
    );
  }
}
