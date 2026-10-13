import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/import/data/excel_import_service.dart';
import 'package:korean_memo/features/study/domain/practice.dart';

void main(){
  late AppDatabase db;
  final day=DateTime(2026,10,13,12);
  setUp(()=>db=AppDatabase(NativeDatabase.memory()));tearDown(()=>db.close());
  Future<int> add(String term,{String? category})async{
    final book=await db.createWordBook(name:'来源',sourceFileName:term);
    await db.importWords(wordBookId:book,source:term,drafts:[WordDraft(korean:term,meaningZh:'释义',partOfSpeech:'名词',category:category)]);
    return (await db.searchLibraryWords(query:term,filter:LibraryFilter.all)).single.word.id;
  }
  var token=0;
  Future<void> rate(int id,int rating,{DateTime? date,SessionOptions? options})=>db.persistReview(wordId:id,submissionToken:'token-${token++}',rating:rating,
    reviewedAt:(date??day).toUtc(),localDay:date??day,durationMs:1000,
    cardMap:{'state':1,'due':(date??day).toUtc().add(const Duration(days:1)).toIso8601String(),'reps':1,'stability':1.0,'difficulty':4.0},reviewLogMap:{},session:options);

  test('unified queue includes untranslated sources and skips paused words',()async{
    final id=await add('curl',category:'工业术语·待补中文');
    await add('하늘');
    expect((await db.nextTrainingWord(const SessionOptions(),day))?.id,id);
    await db.saveSetting('word_status:$id','suspended');
    expect((await db.nextTrainingWord(const SessionOptions(),day))?.korean,'하늘');
  });
  test('checkin is idempotent, uses local calendar day, and keeps streak',()async{
    final id=await add('하늘');
    await expectLater(db.checkIn(day),throwsA(isA<FormatException>()));
    for(final offset in [2,1,0]){ await rate(id,3,date:day.subtract(Duration(days:offset))); }
    await db.checkIn(day);await db.checkIn(day);
    final check=await db.loadCheckins(day);
    expect(check.days,hasLength(3));expect(check.streak,3);expect(check.longest,3);
    expect((await db.loadCheckins(day.add(const Duration(days:2)))).streak,0);
  });
  test('sessions are independent and undo restores cards counters and checkin',()async{
    final id=await add('하늘');await db.setFavorite(id,true);
    const favorites=SessionOptions(daily:false,target:5,filter:LibraryFilter.favorites);
    const all=SessionOptions(daily:false,target:8);
    await db.startSession(favorites,day);await db.startSession(all,day);
    await rate(id,1,options:favorites);
    expect((await db.loadSession(favorites,day)).done,1);
    expect((await db.loadSession(all,day)).done,0);
    expect((await db.loadCheckins(day)).days,hasLength(1));
    expect((await db.undoLastReview(day))?.id,id);
    expect(await db.cardForWord(id),isNull);
    expect((await db.loadDailyPlanProgress(day)).totalDone,0);
    expect((await db.loadSession(favorites,day)).done,0);
    expect((await db.loadCheckins(day)).days,isEmpty);
    expect((await db.searchLibraryWords(query:'',filter:LibraryFilter.favorites)).single.isFavorite,isTrue);
  });
  test('wrong history stays while three good answers graduate a weak word',()async{
    final id=await add('하늘');await rate(id,1);
    expect(await db.searchLibraryWords(query:'',filter:LibraryFilter.wrong),hasLength(1));
    for(var i=0;i<3;i++){ await rate(id,3); }
    expect(await db.searchLibraryWords(query:'',filter:LibraryFilter.wrong),isEmpty);
    expect((await db.searchLibraryWords(query:'',filter:LibraryFilter.all)).single.wrongCount,1);
  });
  test('restoring retains one recovery snapshot including checkin settings',()async{
    await add('하늘');await db.saveSetting('appearance_style','forest');
    final other=AppDatabase(NativeDatabase.memory());addTearDown(other.close);
    await db.restoreBackupSnapshot(await other.createBackupSnapshot());
    expect(await db.searchLibraryWords(query:'',filter:LibraryFilter.all),isEmpty);
    expect(await db.recoverPreviousRestore(),isTrue);
    expect(await db.searchLibraryWords(query:'',filter:LibraryFilter.all),hasLength(1));
    expect(await db.loadSetting('appearance_style'),'forest');
  });
  test('objective grades can be undone without keeping a false test result',()async{
    final id=await add('하늘');const opts=SessionOptions(daily:false,mode:PracticeMode.spelling);
    await db.startSession(opts,day);await rate(id,3,options:opts);
    expect(await db.loadSetting('objective:${dayKey(day)}'),contains('"correct":1'));
    await db.undoLastReview(day);
    expect(await db.loadSetting('objective:${dayKey(day)}'),isNull);
  });
  test('import accepts Korean English pairs and skips Chinese-only rows',(){
    final book=Excel.createExcel();final sheet=book['Sheet1'];
    sheet.appendRow([TextCellValue('韩语'),TextCellValue('英文'),TextCellValue('中文')]);
    sheet.appendRow([TextCellValue('하늘'),TextCellValue('sky'),TextCellValue('')]);
    sheet.appendRow([TextCellValue(''),TextCellValue(''),TextCellValue('只有中文')]);
    final parsed=ExcelImportService().parseFirstSheet(Uint8List.fromList(book.save()!));
    expect(parsed.drafts,hasLength(1));expect(parsed.drafts.single.korean,'sky / 하늘');expect(parsed.invalidRows,1);
  });
  test('spelling comparisons tolerate punctuation and alternative spellings',(){
    expect(answerMatches('안녕 하세요!','안녕하세요'),isTrue);
    expect(answerMatches('sky','heaven / sky'),isTrue);
    expect(answerMatches('skies','sky'),isFalse);
  });
}
