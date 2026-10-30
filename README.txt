SpeakerKeeper  -  使い方
========================================

他のアプリ(YouTube、ゲームなど)から音が出ている間だけ、SoundKeeper で
小さな音を流し、スピーカーのオートスリープを防ぎます。
音が止まってから設定した時間(初期値1分)が経つと SoundKeeper を止めます。


■ 準備
1. このフォルダを好きな場所に置く(例: C:\Tools\SpeakerKeeper)
   ※ 後から場所を動かした場合は、2_add_to_startup.bat をもう一度実行してください
2. SoundKeeper の公式サイト https://veg.by/projects/soundkeeper から
   soundkeeper.7z をダウンロードし、中の「SoundKeeper64.exe」を
   このフォルダ(SpeakerKeeper.ps1 と同じ場所)にコピーする
   ※ ファイル名は「SoundKeeper64.exe」のまま。名前に Sine などを付けないこと
3. 以前スタートアップに入れた SoundKeeper(SoundKeeperSine～.exe など)があれば、
   Win + R →「shell:startup」で開くフォルダから削除し、
   タスクマネージャーで SoundKeeper を終了しておく


■ 動作確認
1_test_run.bat をダブルクリック → 黒い画面が開きます。
YouTubeを再生すると「SoundKeeper 開始」、止めて1分後に「停止」と表示されればOK。
確認できたら画面を閉じて終了します。


■ 常に動かす
2_add_to_startup.bat をダブルクリック。
すぐに裏で起動し、次回からはPC起動時に自動で動きます(画面は出ません)。

やめたいときは 3_remove_from_startup.bat をダブルクリック。


■ 設定の変え方
settings.txt をメモ帳で開き、数字を書き換えて保存するだけ。動作中でも自動で反映されます。

  Frequency      鳴らす音の周波数(Hz)       初期値 500
  Amplitude      鳴らす音の大きさ(%)         初期値 0.075
  LingerSeconds  音が止まってから鳴らす秒数   初期値 60
  Threshold      音が出ていると判断するレベル(通常は変更不要)
  DeviceName     動作させる出力デバイスの名前(この文字を含む出力先のときだけ動く)
                 初期値「スピーカー (Realtek(R) Audio)」。空欄ならすべての出力先で動作
                 名前は 1_test_run.bat の画面の「現在の出力先: ～」で確認できます


■ 注意
・完全に無音の状態からの「最初の再生」では、スピーカーはスリープ中なので
  冒頭のフェードインは残ります。防げるのは、再生中や、止めてから余韻時間内の再生です。
・SoundKeeper が動いている間は、PCが自動でスリープしないことがあります
  (余韻時間が過ぎて止まれば元に戻ります)。
