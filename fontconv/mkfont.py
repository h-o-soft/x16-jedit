from PIL import Image
import os

"""
# cx16-jedit用フォント変換ツール

必要なファイル:
- k8x12_jisx0201.png: JIS X 0201文字セット用のフォント画像(4x12ドット)
- k8x12_jisx0208.png: JIS X 0208文字セット用のフォント画像(8x12ドット)

出力ファイル:
- font0201.bin: JIS X 0201用のフォントデータ
- font0208.bin: JIS X 0208用のフォントデータ

使い方:
1. 必要なフォント画像ファイルを用意
2. このスクリプトを実行
3. 出力された.binファイルをjeditと同じディレクトリに配置

注意:
- 入力画像は白黒の2値画像である必要があります
- フォントは指定されたサイズ(0201は4x12、0208は8x12)で作成されている必要があります
"""


def convert_image_to_font_data(image_path, char_width=8, char_height=12):
    # 画像を開き、グレースケールに変換
    image = Image.open(image_path).convert('L')
    width, height = image.size
    
    # 出力データ
    font_data = []
    
    # 画像を横8ドット、縦12ドットのフォントサイズで処理
    for y in range(0, height, char_height):
        for x in range(0, width, char_width):
            char_data = 0
            for dy in range(char_height):
                row_data = 0
                for dx in range(char_width):
                    pixel = image.getpixel((x + dx, y + dy))
                    # 白い部分を0、黒い部分を1とする
                    bit = 0 if pixel > 128 else 1
                    row_data = (row_data << 1) | bit
                font_data.append(row_data)
    
    return font_data

# 画像ファイルパス
image_path = 'k8x12_jisx0201.png'
# 変換実行
font_data = convert_image_to_font_data(image_path, 4, 12)

# # font_dataを二進数で表示する
# for data in font_data:
#     print(format(data, '08b'))

# font_dataをバイナリファイルに出力する
with open('font0201.bin', 'wb') as f:
    for data in font_data:
        f.write(data.to_bytes(1, 'big'))

# 画像ファイルパス
image_path = 'k8x12_jisx0208.png'
# 変換実行
font_data = convert_image_to_font_data(image_path, 8, 12)

# # font_dataを二進数で表示する
# for data in font_data:
#     print(format(data, '08b'))

# font_dataをバイナリファイルに出力する
with open('font0208.bin', 'wb') as f:
    for data in font_data:
        f.write(data.to_bytes(1, 'big'))

# 雑なオフセット計算の例(unsigned short)
# 64KB * 2 以内じゃないと計算出来ないので注意(どうかと思う)
font_index = 5206
bank = 0
font_index_offset = 3072	# JISX0201のフォントサイズがこのサイズなのでこのぶん常にズラす
# 64kbをまたぐか？
#if font_index > 5461:
if font_index > 5205:
    bank = 1
#    font_index -= 5462
    font_index -= 5206
#    font_index_offset = 8	# 5461文字目が64KB内に4バイト、次のバンクに8バイト入っているので8バイトぶんズラす
    font_index_offset = 8	# 5205文字目が64KB内に4バイト、次のバンクに8バイト入っているので8バイトぶんズラす
font_index = font_index * 12 + font_index_offset

print("bank: ", bank)
print("font_index: ", font_index)

# 8192で割る = 13bitシフト
cx16_bank = (font_index >> 13) | (bank << 3)
print("cx16_bank: ", cx16_bank)



# 全角スペースを32個もった文字列を初期値とする
jisx0201 = '　' * 32
jisx0201 += '　！”＃＄％＆’（）＊＋，‐．／０１２３４５６７８９：；＜＝＞？＠ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ［＼］＾＿｀ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ｛｜｝〜　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン゛゜'
jisx0201 += '　' * 31
jisx0201 += '〜'

# 256文字じゃない場合はエラーを出す
if len(jisx0201) != 256:
    print('jisx0201の文字数が256文字ではありません')
    exit()


# 上記文字列について下記のステップで処理する
# 1. ShiftJISに変換
# 2. 区点コードに変換
# 3. 区から1を引いて96を掛けた値に点の値を足す
# 4. その値に12を掛けるとフォントデータのオフセットになる
# 5. font_dataからそのオフセット位置のデータを取り出す(12バイト分)
# 6. そのデータをバイナリファイルに出力する(連続で)

# font0201.binをまず削除してから処理する
os.remove('font0201.bin')
shift_jis = jisx0201.encode('shift_jis')
print(shift_jis)
# ShiftJISを区点変換する
for i in range(0, len(shift_jis), 2):
    ku = shift_jis[i]
    # kuの値がJISX0201の範囲内の場合はエラーを出して終了
    if ku <= 0x7f or (ku >= 0xa1 and ku <= 0xdf):
        print('JISX0201の範囲外の文字が含まれています [', ku, ']', i)
        exit()

    ten = shift_jis[i+1]

    if ku <= 0x9f:
        if ten < 0x9f:
            ku = (ku << 1) - 0x102
        else:
            ku = (ku << 1) - 0x101
    else:
        if ten < 0x9f:
            ku = (ku << 1) - 0x182
        else:
            ku = (ku << 1) - 0x181

    if ten < 0x7f:
        ten -= 0x40
    elif ten < 0x9f:
        ten -= 0x41
    else:
        ten -= 0x9f

    # 区点からフォントオフセットに変換
    code = ku * 94 + ten
    print(code)

    # フォントデータのオフセット
    offset = code * 12
    # フォントデータをバイナリファイルに出力する

    with open('font0208.bin', 'rb') as f:
        f.seek(offset)
        font_data = f.read(12)
        with open('font0201.bin', 'ab') as f:
            f.write(font_data)

# font0201.binファイルを font0201_dat に読み込む
with open('font0201.bin', 'rb') as f:
    font0201_dat = f.read()
