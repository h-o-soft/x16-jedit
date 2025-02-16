from dataclasses import dataclass, field
from typing import List

"""
# cx16-jedit用辞書変換ツール

必要なファイル:
- SKK-JISYO.M: SKK形式の辞書ファイル

出力ファイル:
- skkdicm.bin: tinyskk用のバイナリ辞書ファイル

使い方:
1. SKK-JISYO.Mを同じフォルダに配置
2. このスクリプトを実行
3. 出力されたskkdicm.binをjeditと同じディレクトリに配置

注意:
- 入力辞書はSKK形式で、EUC-JPで保存されている必要があります
- 出力される辞書はtinyskk専用のバイナリ形式です
"""

# 辞書フォーマット

# +0 : 'DIC' + 0
# +4 : 名詞エントリ「あ」のオフセットアドレス L M H (3bytes)
# +7 : 名詞エントリ「い」のオフセットアドレス L M H (3bytes)
# ....
# 69 * 3 bytes = 207bytesの名詞エントリ
# 69 * 3 bytes = 207bytesの動詞エントリ


# 変換する辞書ファイル名(決め打ち)
dic_path = "SKK-JISYO.M"

# 出力する辞書ファイル名
output_path = "skkdicm.bin"

offset_keys = [
    "あ",   #; 0
    "ぃ",   #; 1
    "い",   #; 2
    "ぅ",   #; 3
    "う",   #; 4
    "ぇ",   #; 5
    "え",   #; 6
    "ぉ",   #; 7
    "お",   #; 8
    "か",   #; 9
    "が",   #; 10
    "き",   #; 11
    "ぎ",   #; 12
    "く",   #; 13
    "ぐ",   #; 14
    "け",   #; 15
    "げ",   #; 16
    "こ",   #; 17
    "ご",   #; 18
    "さ",   #; 19
    "ざ",   #; 20
    "し",   #; 21
    "じ",   #; 22
    "す",   #; 23
    "ず",   #; 24
    "せ",   #; 25
    "ぜ",   #; 26
    "そ",   #; 27
    "ぞ",   #; 28
    "た",   #; 29
    "だ",   #; 30
    "ち",   #; 31
    "ぢ",   #; 32
    "っ",   #; 33
    "つ",   #; 34
    "づ",   #; 35
    "て",   #; 36
    "で",   #; 37
    "と",   #; 38
    "ど",   #; 39
    "な",   #; 40
    "に",   #; 41
    "ぬ",   #; 42
    "ね",   #; 43
    "の",   #; 44
    "は",   #; 45
    "ば",   #; 46
    "ぱ",   #; 47
    "ひ",   #; 48
    "び",   #; 49
    "ぴ",   #; 50
    "ふ",   #; 51
    "ぶ",   #; 52
    "ぷ",   #; 53
    "へ",   #; 54
    "べ",   #; 55
    "ぺ",   #; 56
    "ほ",   #; 57
    "ぼ",   #; 58
    "ぽ",   #; 59
    "ま",   #; 60
    "み",   #; 61
    "む",   #; 62
    "め",   #; 63
    "も",   #; 64
    "ゃ",   #; 65
    "や",   #; 66
    "ゅ",   #; 67
    "ゆ",   #; 68
    "ょ",   #; 69
    "よ",   #; 70
    "ら",   #; 71
    "り",   #; 72
    "る",   #; 73
    "れ",   #; 74
    "ろ",   #; 75
    "ゎ",   #; 76
    "わ",   #; 77
    "ゐ",   #; 78
    "ゑ",   #; 79
    "を",   #; 80
    "ん"    #; 81
]

def get_empty_list():
    return []

@dataclass
class CharOffsetEntry:
    key: str
    offset: int = 0
    header_size: int = 0
    entry_size: int = 0
    entries: list = field(default_factory=get_empty_list)

@dataclass
class DicEntry:
    all_size: int = 0
    key: str = ""
    kouho_count: int = 0
    kouho: list = field(default_factory=get_empty_list)

    def update_all_size(self):
        # keyをShift-JISにエンコードしたサイズを得る
        sjis = self.key.encode("shift_jis")
        self.all_size = 2 + len(sjis) + 1 +  1   # sizeof(all_size) + sizeof(key) + 0 +  kouho_count(1byte)
        # kouhoの各項目をShift-JISにエンコードしたサイズを得てself.all_sizeに加算する
        for k in self.kouho:
            sjis = k.encode("shift_jis")
            self.all_size += len(sjis) + 1
        # これで all_sizeが計算出来ているはず

meishi_offset_entries = [CharOffsetEntry(key=k) for k in offset_keys]
doushi_offset_entries = [CharOffsetEntry(key=k) for k in offset_keys]

# 一応計算でヘッダサイズを求めておく
all_header_size = 4
for e in meishi_offset_entries:
    all_header_size += 3
for e in doushi_offset_entries:
    all_header_size += 3


# 2bytes : このエントリの総バイト数。ただし各エントリグループの先頭の場合は最上位ビットが立つ(つまり検索してる間に最上位ビットが立ったらそこで抜ける必要がある)
# variable : このエントリのキー文字列(0で終わる)
# 1byte : 候補の個数(n) ※コンバータ作成時に256をオーバーする事が判明したら2bytesに拡張する
# variable : 候補文字列1(0で終わる)
# ....
# variable : 候補文字列n(0で終わる)
# 次のエントリ

all_entries = []

# 1. 辞書ファイルを読み込む
#   フォーマットはEUC-JP(のはず)
#   一行ずつ読む
#   行頭が ; の場合はコメントなので飛ばす
#   行頭が半角文字の場合も飛ばす
with open(dic_path, "r", encoding="euc-jp") as f:
    lines = f.readlines()
    # 改行を削除
    lines = [line.rstrip() for line in lines]
    for line in lines:
        if line[0] == ";":
            continue
        if ord(line[0]) < 0x80:
            continue
        # 処理開始。形式としては
        # (全角文字)(任意の数の空白またはタブ)/(候補1)/候補2)/.../(候補n)/
        # のようになっている
        # まずは、スペースまたはタブで区切られている全角文字を取得
        entry = DicEntry()
        dicinfo = line.split()
        dickey = dicinfo[0]
        entry.key = dickey
        # 次に候補を / で区切って取得。ただし行頭、行末にも / がある場合があるので、あった場合は除外する
        kouho = [part for part in dicinfo[1].split("/") if part]
        entry.kouho_count = len(kouho)
        for k in kouho:
            entry.kouho.append(k)
        all_entries.append(entry)
        
        # dickeyをShift-JISにエンコード
        sjis = dickey.encode("shift_jis")

# とりあえず必要なものは得られた
for entry in all_entries:
    entry.update_all_size()
    # entry.keyの末尾が半角文字、というか、アルファベットかどうか調べる
    target_offset_entries = None
    if ord(entry.key[-1]) < 0x80:
        # 半角なので動詞扱いである(doushi_offset_entriesに追加)
        target_offset_entries = doushi_offset_entries
    else:
        # 全角なので名詞扱いである(meishi_offset_entriesに追加)
        target_offset_entries = meishi_offset_entries
    # キーの一文字目を探す
    key_head = entry.key[0]
    # doushi_offset_entriesの中からkey_headに一致するものを探す
    added = False
    for e in target_offset_entries:
        if e.key == key_head:
            # 一致したものにentryを追加する
            e.entries.append(entry)
            added = True
            break
    if not added:
        # 一致するものがなかったのでエラーを出して終了
        print("Error: doushi_offset_entriesに一致するものがなかった")
        exit(1)

for e in doushi_offset_entries:
    e.entry_size = 0    # 念の為初期化
    first = True
    for entry in e.entries:
        if first:
            # 先頭のエントリなので最上位ビットを立てる
            entry.all_size |= 0x8000
            first = False
        # entry_sizeを更新
        e.entry_size += entry.all_size & 0x7fff

for e in meishi_offset_entries:
    e.entry_size = 0    # 念の為初期化
    first = True
    for entry in e.entries:
        if first:
            # 先頭のエントリなので最上位ビットを立てる
            entry.all_size |= 0x8000
            first = False
        # entry_sizeを更新
        e.entry_size += entry.all_size & 0x7fff


data_offset = all_header_size
# 名詞エントリのオフセットを設定
for e in meishi_offset_entries:
    if len(e.entries) == 0:
        e.offset = 0
    else:
        e.offset = data_offset
    data_offset += e.entry_size
# 動詞エントリのオフセットを設定
for e in doushi_offset_entries:
    if len(e.entries) == 0:
        e.offset = 0
    else:
        e.offset = data_offset
    data_offset += e.entry_size

print("Dictionary All Size : ")
print(data_offset)

with open(output_path, "wb") as f:
    # ヘッダ部分を書き込む
    f.write(b"DIC\x00")
    # 名詞エントリのオフセットを1バイトずつ書き込む
    # ただし、先頭からのバイト数ではなく、データブロックを8KBで区切った場合のバンク番号をHに入れ、L、Mにはそのバンク内のオフセットを入れる
    for e in meishi_offset_entries:
        offset = e.offset % 8192
        f.write(offset.to_bytes(2, "little"))
        bank = e.offset // 8192
        f.write(bank.to_bytes(1, "little"))
    for e in doushi_offset_entries:
        offset = e.offset % 8192
        f.write(offset.to_bytes(2, "little"))
        bank = e.offset // 8192
        f.write(bank.to_bytes(1, "little"))
    # 名詞エントリを書き込む
    for e in meishi_offset_entries:
        for entry in e.entries:
            # 1. このエントリの総バイト数からエントリーのキー文字列サイズと自分自身のサイズを引いたもの
            skip_size = entry.all_size - 2 - len(entry.key.encode("shift_jis")) - 1
            f.write(skip_size.to_bytes(2, "little"))
            # 2. このエントリのキー文字列
            sjis = entry.key.encode("shift_jis")
            f.write(sjis)
            f.write(b"\x00")
            # 3. 候補の個数
            f.write(entry.kouho_count.to_bytes(1, "little"))
            # 4. 候補文字列
            for k in entry.kouho:
                sjis = k.encode("shift_jis")
                f.write(sjis)
                f.write(b"\x00")
    # 動詞エントリを書き込む
    for e in doushi_offset_entries:
        for entry in e.entries:
            # 1. このエントリの総バイト数からエントリーのキー文字列サイズと自分自身のサイズを引いたもの
            skip_size = entry.all_size - 2 - len(entry.key.encode("shift_jis")) - 1
            f.write(skip_size.to_bytes(2, "little"))
            # 2. このエントリのキー文字列
            sjis = entry.key.encode("shift_jis")
            f.write(sjis)
            f.write(b"\x00")
            # 3. 候補の個数
            f.write(entry.kouho_count.to_bytes(1, "little"))
            # 4. 候補文字列
            for k in entry.kouho:
                sjis = k.encode("shift_jis")
                f.write(sjis)
                f.write(b"\x00")
