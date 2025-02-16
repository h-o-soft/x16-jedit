

; tinyskk
; 
;   Commander X16でSKKっぽい漢字変換を行う何か

; # 内部モード
; モード0: 直接入力状態。母音がダイレクトに返る。
; モード1: 子音を入れて次の子音または母音待ち状態。母音で文字が確定すると文字として返る。qでひらがなカタカナを切り替えるとキャンセルしてモード0に戻る.l
; モード2: 一文字目が大文字で、漢字入力が開始された状態。母音を入力すると読み仮名として記録されるが、呼び出し元側にはまだ文字としては返らない
; モード3: モード2の状態で子音を入れた状態。次の子音または母音待ち状態。母音が入ると(というか文字が確定すると)読み仮名として記録される。が、呼び出し元側にはまだ文字として返らない。
; モード4: モード2またはモード3でスペースキーを押して変換候補が出ている状態。スペースキーで変換候補をローテーションさせ、Enterで確定する。確定後モード0に戻る。ESCで漢字を消して読み仮名を復帰してモード2に戻る。
; モード5: モード2またはモード3で文字を入力した時にそれが大文字だった場合の動詞変換モード1。母音の場合。例えば「KaU」だと「▼買う」となり、この状態で候補選択になる。「買u」という候補なので加工して表示。送り仮名を記録した方がいいかも。
; モード6: モード2またはモード3で文字を入力した時にそれが大文字だった場合の動詞変換モード2。子音の場合。例えば「MiR」だと「▽見*r」となり、母音入力待ちになる。母音入力がされるとモード5に移行する。ESCかqでモード2に戻る。
; ……これくらいか？ややこしい。

; # 使い方(癖があります)
; 基本的には proces_key_input() を呼ぶだけで、戻り値のuwordを表示したり、コントロールコードとして処理したりすれば良い
; 半角は下位8ビットに入り、全角文字はuwordとして1文字として一回で返る(分割して届く事はない)
; 
; 内部では、 result = tskk.input(ch) という呼び出しをしていて、確定文字列がある場合はresultが0以外になる
; resultをjtxt.print(result)で表示出来るが、そのあと、例えば送り入力状態になっている事があるので、
; result = tskk.update()
; として、やはりresultに確定文字列が入るかどうかチェックして、0以外の場合、jtxt.print(result)しないといけない。
; このあたりを全て process_key_input で行っているが、だいぶ美しくないのでリファクタリングした方が良い。
; 
; これ以外の▽や▼、*や、漢字入力注の文字列は、一切resultには入ってこず、全てtinyskk内でjtxt.printされる。

; # バッファについて
; 確定文字列→ result_string
; 読み仮名→ kanji_yomigana
; 

; あとは気合いで読み解いてください……！

tskk {
    const uword KANA_NEXT = $80

    const ubyte SKKMODE_INIT = 0
    const ubyte SKKMODE_ROMA = 1
    const ubyte SKKMODE_KANJI = 2
    const ubyte SKKMODE_KANJI_OKURI = 3
    const ubyte SKKMODE_KANJI_KOUHO = 4
    const ubyte SKKMODE_KANJI_DOUSHI = 5
    const ubyte SKKMODE_KANJI_DOUSHI_OKURI = 6
    const ubyte SKKMODE_KANJI_DOUSHI_KOUHO = 7
    const ubyte SKKMODE_DIRECT = 8

    const ubyte GETCHMODE_WAIT = 0;
    const ubyte GETCHMODE_SEND_STR = 1;

    ; ローマ字入力用テーブル
    uword[] @nosplit chr_table = [
        chr0_table, chr1_table, chr2_table, chr3_table, chr4_table, chr5_table, chr6_table, chr7_table, chr8_table, chr9_table,
        chr10_table, chr11_table, chr12_table, chr13_table, chr14_table, chr15_table, chr16_table, chr17_table, 0, chr19_table,
        0,0,0,0,0,0,0,0,0,0,
        chr30_table, chr31_table, chr32_table, chr33_table, chr34_table, chr35_table, chr36_table, chr37_table, chr38_table, chr39_table,
        chr40_table, chr41_table, chr42_table, chr43_table, chr44_table, chr45_table, chr46_table, chr47_table, chr48_table, chr49_table,
        chr50_table, chr51_table, chr52_table
    ]

    ; 1文字目のテーブル
    uword[] @nosplit chr0_table = [
        'a' + (0 * 256),
        'i' + (1 * 256),
        'u' + (2 * 256),
        'e' + (3 * 256),
        'o' + (4 * 256),
        ; かきくけこ
        ; kya kyu kyo
        'k' + (1 * 256) + KANA_NEXT,
        ; がぎぐげご
        ; ぎゃ、ぎゅ、ぎょ
        'g' + (2 * 256) + KANA_NEXT,
        ; さしすせそ / si or shi
        ; sya syu syo / sha shu sho
        ; sye she
        's' + (3 * 256) + KANA_NEXT,
        ; ざじずぜぞ
        ; zya zyu zyo
        ; zye
        'z' + (4 * 256) + KANA_NEXT,
        ; じ ji
        ; ja ju jo
        ; je
        'j' + (5 * 256) + KANA_NEXT,
        ; たちつてと / tu or tsu
        ; tya tyu tyo
        ; tye ちぇ
        ; tsa tse tso つぁ つぇ つぉ
        ; thi てぃ
        't' + (6 * 256) + KANA_NEXT,
        ; ち chi
        ; cha chu cho
        ; che
        'c' + (7 * 256) + KANA_NEXT,
        ; だぢづでど
        ; dya dyu dyo
        ; dye
        ; dhi dhu
        'd' + (8 * 256) + KANA_NEXT,
        ; なにぬねの
        ; nya nyu nyo
        ; nn ん
        'n' + (9 * 256) + KANA_NEXT,
        ; はひふへほ
        ; hya hyu hyo
        'h' + (10 * 256) + KANA_NEXT,
        ; ふ fu
        ; fa fi fe fo
        'f' + (11 * 256) + KANA_NEXT,
        ; ばびぶべぼ
        ; bya byu byo
        'b' + (12 * 256) + KANA_NEXT,
        ; ぱぴぷぺぽ
        ; pya pyu pyo
        'p' + (13 * 256) + KANA_NEXT,
        ; まみむめも
        ; mya myu myo
        'm' + (14 * 256) + KANA_NEXT,
        ; やゆよ
        'y' + (15 * 256) + KANA_NEXT,
        ; らりるれろ
        ; rya ryu ryo
        'r' + (16 * 256) + KANA_NEXT,
        ; わを
        'w' + (17 * 256) + KANA_NEXT,
        ; ぁぃぅぇぉ
        ; ヵ(xka) ヶ(xke)
        ; ャ(xya) ュ(xyu) ョ(xyo)
        ; っ(xtu)
        ; ゎ(xwa)わ
        'x' + (19 * 256) + KANA_NEXT,
        ; ー
        '-' + (134 * 256),
        ',' + (135 * 256),
        '.' + (136 * 256),
        0
    ]
    ; k のテーブル(1)
    uword[] @nosplit chr1_table = [
        'a' + (5 * 256),    ; か
        'i' + (6 * 256),    ; き
        'u' + (7 * 256),    ; く
        'e' + (8 * 256),    ; け
        'o' + (9 * 256),    ; こ

        'y' + (30 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr30_table = [
        'a' + (81 * 256),    ; きゃ
        'u' + (82 * 256),    ; きゅ
        'o' + (83 * 256),     ; きょ
        0
    ]
    uword[] @nosplit chr2_table = [
        'a' + (10 * 256),    ; が
        'i' + (11 * 256),    ; ぎ
        'u' + (12 * 256),    ; ぐ
        'e' + (13 * 256),    ; げ
        'o' + (14 * 256),    ; ご

        'y' + (31 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr31_table = [
        'a' + (84 * 256),    ; ぎゃ
        'u' + (85 * 256),    ; ぎゅ
        'o' + (86 * 256),    ; ぎょ
        0
    ]
    uword[] @nosplit chr3_table = [
        'a' + (15 * 256),    ; さ
        'i' + (16 * 256),    ; し
        'u' + (17 * 256),    ; す
        'e' + (18 * 256),    ; せ
        'o' + (19 * 256),    ; そ

        'h' + (32 * 256) + KANA_NEXT,
        'y' + (33 * 256) + KANA_NEXT,
        'h' + (33 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr32_table = [
        'i' + (16 * 256),    ; し
        'a' + (87 * 256),    ; しゃ
        'u' + (88 * 256),    ; しゅ
        'o' + (89 * 256),    ; しょ
        'e' + (115 * 256),    ; しぇ
        0
    ]
    uword[] @nosplit chr33_table = [
        'a' + (87 * 256),    ; しゃ
        'u' + (88 * 256),    ; しゅ
        'o' + (89 * 256),    ; しょ
        'e' + (115 * 256),    ; しぇ
        0
    ]
    uword[] @nosplit chr4_table = [
        'a' + (20 * 256),    ; ざ
        'i' + (21 * 256),    ; じ
        'u' + (22 * 256),    ; ず
        'e' + (23 * 256),    ; ぜ
        'o' + (24 * 256),    ; ぞ

        'y' + (34 * 256) + KANA_NEXT,

        '.' + (137 * 256),  ; …
        ',' + (138 * 256),  ; ‥
        0
    ]
    uword[] @nosplit chr34_table = [
        'a' + (90 * 256),    ; じゃ
        'u' + (91 * 256),    ; じゅ
        'o' + (92 * 256),    ; じょ
        'e' + (114 * 256),   ; じぇ
        0
    ]
    uword[] @nosplit chr5_table = [
        'i' + (21 * 256),   ; じ
        'a' + (90 * 256),   ; じゃ
        'u' + (91 * 256),   ; じゅ
        'o' + (92 * 256),   ; じょ
        'e' + (114 * 256),  ; じぇ
        0
    ]
    uword[] @nosplit chr6_table = [
        'a' + (25 * 256),    ; た
        'i' + (26 * 256),    ; ち
        'u' + (27 * 256),    ; つ
        'e' + (28 * 256),    ; て
        'o' + (29 * 256),    ; と

        'y' + (35 * 256) + KANA_NEXT,
        'h' + (36 * 256) + KANA_NEXT,
        's' + (37 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr35_table = [
        'a' + (93 * 256),    ; ちゃ
        'u' + (94 * 256),    ; ちゅ
        'o' + (95 * 256),    ; ちょ
        'e' + (116 * 256),   ; ちぇ
        0
    ]
    uword[] @nosplit chr36_table = [
        'i' + (126 * 256),    ; てぃ
        0
    ]
    uword[] @nosplit chr37_table = [
        'a' + (118 * 256),    ; つぁ
        'e' + (120 * 256),   ; つぇ
        'o' + (121 * 256),   ; つぉ
        'u' + (27 * 256),    ; つ
        0
    ]
    uword[] @nosplit chr7_table = [
        'h' + (38 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr38_table = [
        'i' + (26 * 256),    ; ち
        'a' + (93 * 256),    ; ちゃ
        'u' + (94 * 256),    ; ちゅ
        'o' + (95 * 256),    ; ちょ
        'e' + (116 * 256),   ; ちぇ
        0
    ]
    uword[] @nosplit chr8_table = [
        'a' + (30 * 256),    ; だ
        'i' + (31 * 256),    ; ぢ
        'u' + (32 * 256),    ; づ
        'e' + (33 * 256),    ; で
        'o' + (34 * 256),    ; ど

        'y' + (39 * 256) + KANA_NEXT,
        'h' + (40 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr39_table = [
        'a' + (127 * 256),    ; ぢゃ
        'u' + (128 * 256),    ; ぢゅ
        'o' + (129 * 256),    ; ぢょ
        'e' + (117 * 256),   ; ぢぇ
        0
    ]
    uword[] @nosplit chr40_table = [
        'i' + (133 * 256),   ; でぃ
        'u' + (130 * 256),  ; でゅ
        0
    ]
    uword[] @nosplit chr9_table = [
        'a' + (35 * 256),    ; な
        'i' + (36 * 256),    ; に
        'u' + (37 * 256),    ; ぬ
        'e' + (38 * 256),    ; ね
        'o' + (39 * 256),    ; の
        'n' + (70 * 256),    ; ん

        'y' + (41 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr41_table = [
        'a' + (96 * 256),   ; にゃ
        'u' + (97 * 256),   ; にゅ
        'o' + (98 * 256),   ; にょ
        0
    ]
    uword[] @nosplit chr10_table = [
        'a' + (40 * 256),    ; は
        'i' + (41 * 256),    ; ひ
        'u' + (42 * 256),    ; ふ
        'e' + (43 * 256),    ; へ
        'o' + (44 * 256),    ; ほ

        'y' + (42 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr42_table = [
        'a' + (99 * 256),    ; ひゃ
        'u' + (100 * 256),   ; ひゅ
        'o' + (101 * 256),   ; ひょ
        0
    ]
    uword[] @nosplit chr11_table = [
        'a' + (122 * 256),   ; ふぁ
        'i' + (123 * 256),   ; ふぃ
        'u' + (42 * 256),    ; ふ
        'e' + (124 * 256),   ; ふぇ
        'o' + (125 * 256),   ; ふぉ
        0
    ]
    uword[] @nosplit chr12_table = [
        'a' + (45 * 256),    ; ば
        'i' + (46 * 256),    ; び
        'u' + (47 * 256),    ; ぶ
        'e' + (48 * 256),    ; べ
        'o' + (49 * 256),    ; ぼ

        'y' + (43 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr43_table = [
        'a' + (102 * 256),   ; びゃ
        'u' + (103 * 256),   ; びゅ
        'o' + (104 * 256),   ; びょ
        0
    ]
    uword[] @nosplit chr13_table = [
        'a' + (50 * 256),   ; ぱ
        'i' + (51 * 256),   ; ぴ
        'u' + (52 * 256),   ; ぷ
        'e' + (53 * 256),   ; ぺ
        'o' + (54 * 256),   ; ぽ

        'y' + (44 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr44_table = [
        'a' + (105 * 256),   ; ぴゃ
        'u' + (106 * 256),   ; ぴゅ
        'o' + (107 * 256),   ; ぴょ
        0
    ]
    uword[] @nosplit chr14_table = [
        'a' + (55 * 256),    ; ま
        'i' + (56 * 256),    ; み
        'u' + (57 * 256),    ; む
        'e' + (58 * 256),    ; め
        'o' + (59 * 256),    ; も

        'y' + (45 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr45_table = [
        'a' + (108 * 256),   ; みゃ
        'u' + (109 * 256),   ; みゅ
        'o' + (110 * 256),   ; みょ
        0
    ]
    uword[] @nosplit chr15_table = [
        'a' + (60 * 256),    ; や
        'u' + (61 * 256),    ; ゆ
        'o' + (62 * 256),    ; よ
        0
    ]
    uword[] @nosplit chr16_table = [
        'a' + (63 * 256),    ; ら
        'i' + (64 * 256),    ; り
        'u' + (65 * 256),    ; る
        'e' + (66 * 256),    ; れ
        'o' + (67 * 256),    ; ろ

        'y' + (46 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr46_table = [
        'a' + (111 * 256),   ; りゃ
        'u' + (112 * 256),   ; りゅ
        'o' + (113 * 256),   ; りょ
        0
    ]
    uword[] @nosplit chr17_table = [
        'a' + (68 * 256),    ; わ
        'o' + (69 * 256),    ; を
        0
    ]
    ; uword[] chr18_table = [
    ;     0
    ; ]
    uword[] @nosplit chr19_table = [
        'a' + (71 * 256),    ; ぁ
        'i' + (72 * 256),    ; ぃ
        'u' + (73 * 256),    ; ぅ
        'e' + (74 * 256),    ; ぇ
        'o' + (75 * 256),    ; ぉ

        'k' + (47 * 256) + KANA_NEXT,
        'y' + (48 * 256) + KANA_NEXT,
        't' + (49 * 256) + KANA_NEXT,
        'w' + (52 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr47_table = [
        'a' + (131 * 256),   ; ヵ
        'e' + (132 * 256),   ; ヶ
        0
    ]
    uword[] @nosplit chr48_table = [
        'a' + (76 * 256),    ; ゃ
        'u' + (77 * 256),    ; ゅ
        'o' + (78 * 256),    ; ょ
        0
    ]
    uword[] @nosplit chr49_table = [
        'u' + (79 * 256),    ; っ
        's' + (51 * 256) + KANA_NEXT,
        0
    ]
    uword[] @nosplit chr51_table = [
        'u' + (79 * 256),    ; っ
        0
    ]
    uword[] @nosplit chr50_table = [
        0
    ]
    uword[] @nosplit chr52_table = [
        'a' + (80 * 256),   ; ゎ
        0
    ]

    ; ShiftJISのかな文字テーブル
    str[] kana_table1 = [
        "\x82\xa0",   ; 0
        "\x82\xa2",   ; 1
        "\x82\xa4",   ; 2
        "\x82\xa6",   ; 3
        "\x82\xa8",   ; 4
        "\x82\xa9",   ; 5
        "\x82\xab",   ; 6
        "\x82\xad",   ; 7
        "\x82\xaf",   ; 8
        "\x82\xb1",   ; 9
        "\x82\xaa",   ; 10
        "\x82\xac",   ; 11
        "\x82\xae",   ; 12
        "\x82\xb0",   ; 13
        "\x82\xb2",   ; 14
        "\x82\xb3",   ; 15
        "\x82\xb5",   ; 16
        "\x82\xb7",   ; 17
        "\x82\xb9",   ; 18
        "\x82\xbb",   ; 19
        "\x82\xb4",   ; 20
        "\x82\xb6",   ; 21
        "\x82\xb8",   ; 22
        "\x82\xba",   ; 23
        "\x82\xbc",   ; 24
        "\x82\xbd",   ; 25
        "\x82\xbf",   ; 26
        "\x82\xc2",   ; 27
        "\x82\xc4",   ; 28
        "\x82\xc6",   ; 29
        "\x82\xbe",   ; 30
        "\x82\xc0",   ; 31
        "\x82\xc3",   ; 32
        "\x82\xc5",   ; 33
        "\x82\xc7",   ; 34
        "\x82\xc8",   ; 35
        "\x82\xc9",   ; 36
        "\x82\xca",   ; 37
        "\x82\xcb",   ; 38
        "\x82\xcc",   ; 39
        "\x82\xcd",   ; 40
        "\x82\xd0",   ; 41
        "\x82\xd3",   ; 42
        "\x82\xd6",   ; 43
        "\x82\xd9",   ; 44
        "\x82\xce",   ; 45
        "\x82\xd1",   ; 46
        "\x82\xd4",   ; 47
        "\x82\xd7",   ; 48
        "\x82\xda",   ; 49
        "\x82\xcf",   ; 50
        "\x82\xd2",   ; 51
        "\x82\xd5",   ; 52
        "\x82\xd8",   ; 53
        "\x82\xdb",   ; 54
        "\x82\xdc",   ; 55
        "\x82\xdd",   ; 56
        "\x82\xde",   ; 57
        "\x82\xdf",   ; 58
        "\x82\xe0",   ; 59
        "\x82\xe2",   ; 60
        "\x82\xe4",   ; 61
        "\x82\xe6",   ; 62
        "\x82\xe7",   ; 63
        "\x82\xe8",   ; 64
        "\x82\xe9",   ; 65
        "\x82\xea",   ; 66
        "\x82\xeb",   ; 67
        "\x82\xed",   ; 68
        "\x82\xf0",   ; 69
        "\x82\xf1",   ; 70
        "\x82\x9f",   ; 71
        "\x82\xa1",   ; 72
        "\x82\xa3",   ; 73
        "\x82\xa5",   ; 74
        "\x82\xa7",   ; 75
        "\x82\xe1",   ; 76
        "\x82\xe3",   ; 77
        "\x82\xe5",   ; 78
        "\x82\xc1",   ; 79
        "\x82\xec",   ; 80
        "\x82\xab\x82\xe1",   ; 81
        "\x82\xab\x82\xe3",   ; 82
        "\x82\xab\x82\xe5",   ; 83
        "\x82\xac\x82\xe1",   ; 84
        "\x82\xac\x82\xe3",   ; 85
        "\x82\xac\x82\xe5",   ; 86
        "\x82\xb5\x82\xe1",   ; 87
        "\x82\xb5\x82\xe3",   ; 88
        "\x82\xb5\x82\xe5",   ; 89
        "\x82\xb6\x82\xe1",   ; 90
        "\x82\xb6\x82\xe3",   ; 91
        "\x82\xb6\x82\xe5",   ; 92
        "\x82\xbf\x82\xe1",   ; 93
        "\x82\xbf\x82\xe3",   ; 94
        "\x82\xbf\x82\xe5",   ; 95
        "\x82\xc9\x82\xe1",   ; 96
        "\x82\xc9\x82\xe3",   ; 97
        "\x82\xc9\x82\xe5",   ; 98
        "\x82\xd0\x82\xe1",   ; 99
        "\x82\xd0\x82\xe3",   ; 100
        "\x82\xd0\x82\xe5",   ; 101
        "\x82\xd1\x82\xe1",   ; 102
        "\x82\xd1\x82\xe3",   ; 103
        "\x82\xd1\x82\xe5",   ; 104
        "\x82\xd2\x82\xe1",   ; 105
        "\x82\xd2\x82\xe3",   ; 106
        "\x82\xd2\x82\xe5",   ; 107
        "\x82\xdd\x82\xe1",   ; 108
        "\x82\xdd\x82\xe3",   ; 109
        "\x82\xdd\x82\xe5",   ; 110
        "\x82\xe8\x82\xe1",   ; 111
        "\x82\xe8\x82\xe3",   ; 112
        "\x82\xe8\x82\xe5",   ; 113
        "\x82\xb6\x82\xa5",   ; 114
        "\x82\xb5\x82\xa5",   ; 115
        "\x82\xbf\x82\xa5",   ; 116
        "\x82\xc0\x82\xa5",   ; 117
        "\x82\xc2\x82\x9f",   ; 118
        "\x82\xc2\x82\xa1",   ; 119
        "\x82\xc2\x82\xa5",   ; 120
        "\x82\xc2\x82\xa7",   ; 121
        "\x82\xd3\x82\x9f",   ; 122
        "\x82\xd3\x82\xa1",   ; 123
        "\x82\xd3\x82\xa5",   ; 124
        "\x82\xd3\x82\xa7",   ; 125
        "\x82\xc4\x82\xa1",   ; 126
        "\x82\xc0\x82\xe1"    ; 127
    ]
    str[] kana_table2 = [
        "\x82\xc0\x82\xe3",   ; 128
        "\x82\xc0\x82\xe5",   ; 129
        "\x82\xc5\x82\xe3",   ; 130
        "\x83\x95",   ; 131
        "\x83\x96",    ; 132
        "\x82\xc5\x82\xa1",   ; 133
        "\x81\x5b",   ; 134
        "\x81\x41",   ; 135
        "\x81\x42",    ; 136
        "\x81\x63",   ; 137
        "\x81\x64"    ; 138
;        "あ",   ; 0
;        "い",   ; 1
;        "う",   ; 2
;        "え",   ; 3
;        "お",   ; 4
;        "か",   ; 5
;        "き",   ; 6
;        "く",   ; 7
;        "け",   ; 8
;        "こ",   ; 9
;        "が",   ; 10
;        "ぎ",   ; 11
;        "ぐ",   ; 12
;        "げ",   ; 13
;        "ご",   ; 14
;        "さ",   ; 15
;        "し",   ; 16
;        "す",   ; 17
;        "せ",   ; 18
;        "そ",   ; 19
;        "ざ",   ; 20
;        "じ",   ; 21
;        "ず",   ; 22
;        "ぜ",   ; 23
;        "ぞ",   ; 24
;        "た",   ; 25
;        "ち",   ; 26
;        "つ",   ; 27
;        "て",   ; 28
;        "と",   ; 29
;        "だ",   ; 30
;        "ぢ",   ; 31
;        "づ",   ; 32
;        "で",   ; 33
;        "ど",   ; 34
;        "な",   ; 35
;        "に",   ; 36
;        "ぬ",   ; 37
;        "ね",   ; 38
;        "の",   ; 39
;        "は",   ; 40
;        "ひ",   ; 41
;        "ふ",   ; 42
;        "へ",   ; 43
;        "ほ",   ; 44
;        "ば",   ; 45
;        "び",   ; 46
;        "ぶ",   ; 47
;        "べ",   ; 48
;        "ぼ",   ; 49
;        "ぱ",   ; 50
;        "ぴ",   ; 51
;        "ぷ",   ; 52
;        "ぺ",   ; 53
;        "ぽ",   ; 54
;        "ま",   ; 55
;        "み",   ; 56
;        "む",   ; 57
;        "め",   ; 58
;        "も",   ; 59
;        "や",   ; 60
;        "ゆ",   ; 61
;        "よ",   ; 62
;        "ら",   ; 63
;        "り",   ; 64
;        "る",   ; 65
;        "れ",   ; 66
;        "ろ",   ; 67
;        "わ",   ; 68
;        "を",   ; 69
;        "ん",   ; 70
;        "ぁ",   ; 71
;        "ぃ",   ; 72
;        "ぅ",   ; 73
;        "ぇ",   ; 74
;        "ぉ",   ; 75
;        "ゃ",   ; 76
;        "ゅ",   ; 77
;        "ょ",   ; 78
;        "っ",   ; 79
;        "ゎ",   ; 80
;        "きゃ", ; 81
;        "きゅ", ; 82
;        "きょ", ; 83
;        "ぎゃ", ; 84
;        "ぎゅ", ; 85
;        "ぎょ", ; 86
;        "しゃ", ; 87
;        "しゅ", ; 88
;        "しょ", ; 89
;        "じゃ", ; 90
;        "じゅ", ; 91
;        "じょ", ; 92
;        "ちゃ", ; 93
;        "ちゅ", ; 94
;        "ちょ", ; 95
;        "にゃ", ; 96
;        "にゅ", ; 97
;        "にょ", ; 98
;        "ひゃ", ; 99
;        "ひゅ", ; 100
;        "ひょ", ; 101
;        "びゃ", ; 102
;        "びゅ", ; 103
;        "びょ", ; 104
;        "ぴゃ", ; 105
;        "ぴゅ", ; 106
;        "ぴょ", ; 107
;        "みゃ", ; 108
;        "みゅ", ; 109
;        "みょ", ; 110
;        "りゃ", ; 111
;        "りゅ", ; 112
;        "りょ", ; 113
;        "じぇ", ; 114
;        "しぇ", ; 115
;        "ちぇ", ; 116
;        "ぢぇ", ; 117
;        "つぁ", ; 118
;        "つぃ", ; 119
;        "つぇ", ; 120
;        "つぉ", ; 121
;        "ふぁ", ; 122
;        "ふぃ", ; 123
;        "ふぇ", ; 124
;        "ふぉ", ; 125
;        "てぃ", ; 126
;        "ぢゃ", ; 127
;        "ぢゅ", ; 128
;        "ぢょ"  ; 129
;        "でゅ"  ; 130
;        "ヵ"    ; 131
;        "ヶ"    ; 132
;        "でぃ"  ; 133
    ]

    str backspace_str = "\x08"

    bool is_katakana = false
    ubyte skk_mode = SKKMODE_INIT
    ubyte current_table_num = 0
    ubyte prev_ch = 0
    bool is_doushi_conv = false

    const ubyte MODE_STACK_MAX = 3
    ubyte[MODE_STACK_MAX] mode_stacks
    ubyte mode_stack_num = 0

    ubyte roma_counter = 0
    ubyte okuri_counter = 0
    ubyte update_ch

    ; 結果文字列
    ubyte[16] result_string

    ; 辞書データが存在するメモリバンク
    ubyte dic_bank
    ubyte[82 * 3] dic_meishi_head
    ubyte[82 * 3] dic_doushi_head
    ubyte[] kanji_input_mark = [
        $81, $a4, 0       ; ▽
    ]
    ubyte[] kanji_henkan_mark = [
        $81, $a5, 0       ; ▽
    ]
    ubyte[256] kanji_yomigana
    ubyte[16] doushi_okuri

    uword buff_adr;
    ubyte getch_mode = GETCHMODE_WAIT;

    sub load_dic(str fname_ptr, ubyte bank) -> uword
    {
        cx16.rambank(bank)
        dic_bank = bank
        uword result = diskio.load_raw(fname_ptr, $a000)
        if result != 0
        {
            ; 読み込み成功したので辞書ヘッダを確認
            cx16.rambank(bank)
            if strings.compare($a000, iso:"DIC")== 0
            {
                ; ヘッダが一致したのでヘッダを読み込む
                ; 名詞ヘッダの保存
                sys.memcopy($a000+4,      dic_meishi_head, 82*3)
                sys.memcopy($a000+4+82*3, dic_doushi_head, 82*3)

                skk_mode = SKKMODE_DIRECT
                current_table_num = 0
                result_string[0] = 0
                kanji_yomigana[0] = 0
                update_ch = $ff
            }
        }
        return result
    }

    ubyte current_dic_bank
    uword current_dic_addr

    uword dic_data_size
    ubyte[16] key_str
    ubyte kouho_count
    ubyte kouho_index
    uword[64] @nosplit kouho_ptrs
    ubyte[256] kouho_buffer

    sub add_himem_address()
    {
        current_dic_addr++
        if current_dic_addr == $c000
        {
            current_dic_bank++
            cx16.rambank(current_dic_bank)
            current_dic_addr = $a000
        }
    }

    sub set_himem_address(ubyte bank, uword addr)
    {
        current_dic_bank = bank + dic_bank
        current_dic_addr = addr
    }

    sub get_himem_ubyte() -> ubyte
    {
        ubyte result
        cx16.rambank(current_dic_bank)
        result = @(current_dic_addr)
        add_himem_address()
        return result
    }

    sub get_himem_uword() -> uword
    {
        uword result = get_himem_ubyte()
        result = result + (get_himem_ubyte() as uword) * 256
        return result
    }

    sub setup_dic_kouho(ubyte ch, bool is_doushi)
    {
        uword base_addr
        uword chw = ch
        if is_doushi
        {
            base_addr = &dic_doushi_head
        } else {
            base_addr = &dic_meishi_head 
        }
        ubyte bank = @(base_addr + chw*3 + 2)
        uword addr  = @(base_addr + chw*3 + 1)
        addr = $a000 + (addr << 8) | @(base_addr + chw*3)
        set_himem_address(bank, addr)
    }

    sub fetch_dic_key() -> bool
    {
        dic_data_size = get_himem_uword()
        bool result = (dic_data_size & $8000) != 0
        dic_data_size &= $7fff    ; 最上位ビットが立っていると例えば「あ」から「か」に移ったという事なので検索を打ち切れる

        ; 候補文字を得る
        ubyte idx = 0
        repeat {
            key_str[idx] = get_himem_ubyte()
            if key_str[idx] == 0
            {
                break
            }
            idx++
        }
        return result
    }

    sub search_dic_kouho(uword str_ptr) -> uword
    {
        bool is_found = false
        void fetch_dic_key()
        repeat {
            ; 比較するよ
            if strings.compare(str_ptr, key_str) == 0
            {
                is_found = true
                break
            } 
            ; dic_data_sizeぶんだけ無駄に読む
            repeat dic_data_size
            {
                void get_himem_ubyte()
            }
            ; 次の候補を得る
            if fetch_dic_key()
            {
                ; 文字グループをまたいだので抜ける
                break
            }
        }
        if not is_found
        {
            return 0
        }
        ; 全候補を拾う
        kouho_count = get_himem_ubyte()
        ubyte i
        ubyte idx = 0
        for i in 0 to kouho_count-1
        {
            kouho_ptrs[i] = &kouho_buffer[idx]
            repeat{
                kouho_buffer[idx] = get_himem_ubyte()
                if kouho_buffer[idx] == 0
                {
                    idx++
                    break
                }
                idx++
            }
        }
        ; 候補の一つ目(のポインタ)を返す
        kouho_index = 0
        return kouho_ptrs[0]
    }

    sub convert_kanji(uword sptr, bool is_doushi) -> uword
    {
        uword ch = @(sptr);
        ; 半角文字はとりあえず変換対象ではない(事にする)
        if (ch <= $7f or (ch >= $a1 and ch <= $df))
        {
            txt.print("(hankaku)")
            return 0
        }
        uword ch2 = @(sptr+1);
        ch = (ch << 8) + ch2
        ch = ch - $82a0
        ubyte chb = lsb(ch)
        if chb > 82
        {
            txt.print("(out of range)")
            return 0
        }
        setup_dic_kouho(chb, is_doushi)
        return search_dic_kouho(sptr)
    }

    ; モードをスタックする
    sub push_mode(ubyte ch)
    {
        if mode_stack_num == MODE_STACK_MAX
        {
            return
        }
        mode_stacks[mode_stack_num] = current_table_num
        mode_stack_num++

        current_table_num = ch
    }

    sub pop_mode()
    {
        if mode_stack_num == 0
        {
            current_table_num = 0
            return
        }
        mode_stack_num--
        current_table_num = mode_stacks[mode_stack_num]
    }

    sub clear_mode()
    {
        mode_stack_num = 0
        current_table_num = 0
        roma_counter = 0
    }

    sub print_backspace(ubyte ilen)
    {
        ubyte i
        if ilen == 0
        {
            return
        }
        for i in 0 to ilen-1
        {
            jtxt.print(backspace_str)
        }
    }
    
    sub set_table_string(ubyte idx)
    {
        result_string[0] = 0
        uword table_ptr
        if idx < 128
        {
            prev_ch = 0
            table_ptr = kana_table1[idx]
        } else {
            prev_ch = 0
            table_ptr = kana_table2[idx-128]
        }
        uword target_ptr = result_string

        void strings.append(target_ptr, table_ptr)

        if is_katakana
        {
            ubyte i = 0
            ubyte ch
            repeat {
                if @(target_ptr + i) == 0
                {
                    break
                }
                if @(target_ptr + i) < $80
                {
                    i++
                    continue
                }
                ch = @(target_ptr + i + 1)
                if @(target_ptr + i) >= $82 and ch >= $9f and ch <= $f1
                {
                    @(target_ptr + i) =$83
                    if ch <= $dd
                    {
                        @(target_ptr + i + 1) = ch - $5f
                    } else {
                        @(target_ptr + i + 1) = ch - $5e
                    }
                }
                i += 2
            }
        }
    }

    sub get_string_count(uword sptr) -> ubyte
    {
        ubyte idx = 0
        ubyte count = 0
        repeat {
            ubyte ch = @(sptr + idx)
            if ch == 0
            {
                break
            }
            if (ch <= $7f or (ch >= $a1 and ch <= $df))
            {
                idx++
            } else {
                idx += 2
            }
            count++
        }
        return count
    }

    sub yomigana_backspace() -> bool
    {
        ubyte idx = 0
        ubyte count = 0
        uword last_ptr = 0
        uword sptr = kanji_yomigana
        repeat {
            ubyte ch = @(sptr + idx)
            if ch == 0
            {
                break
            }
            last_ptr = sptr + idx
            if (ch <= $7f or (ch >= $a1 and ch <= $df))
            {
                idx++
            } else {
                idx += 2
            }
            count++
        }
        if last_ptr != 0
        {
            @(last_ptr) = 0
        }
        return kanji_yomigana[0] == 0
    }

    bool is_break
    bool with_shift
    uword result_string_ptr

    ; 1文字入力があった場合の処理
    sub input(ubyte ch) -> uword
    {
        ; 複雑なのでステートマシン的に振り分ける
        is_break = false
        with_shift = ch >= $c1 and ch <= $da
        result_string_ptr = 0

        ; このへんなんだっけ……直値がなんだったか忘れた
        if ch == 157
        {
            ch = 19
        } else if ch == 145
        {
            ch = 5
        }

        while not is_break
        {
            when skk_mode {
                SKKMODE_INIT -> normal_input(ch)
                SKKMODE_ROMA -> normal_input(ch)
                SKKMODE_KANJI -> kanji_input(ch)
                SKKMODE_KANJI_OKURI -> kanji_input(ch)
                SKKMODE_KANJI_KOUHO -> kanji_kouho_input(ch)
                SKKMODE_KANJI_DOUSHI_KOUHO -> kanji_doushi_kouho(ch)
                SKKMODE_DIRECT -> direct_input(ch)
            }
        }
        return result_string_ptr
    }

    sub hirakata_check(ubyte ch) -> bool
    {
        if ch == 'q'
        {
            ; かたかなひらがな切り替え
            is_katakana = not is_katakana
            return true
        }
        return false
    }

    sub normal_input(ubyte ch)
    {
        ; 大文字が入力された場合は漢字入力モードに遷移する
        if with_shift
        {
            ; 漢字入力開始状態に遷移する
            with_shift = false
            skk_mode = SKKMODE_KANJI
            jtxt.print(kanji_input_mark)
            kanji_yomigana[0] = 0
            return
        }

        ; ひらがな/カタカナ切り替えだけして終了
        if hirakata_check(ch)
        {
            is_break = true
            return
        }

        ; 通常入力モードでBackspaceが押されたら $14自体を返す
        if ch == $14
        {
            ; ローマ字が1文字でも入力されている場合はこっち
            if roma_counter > 0
            {
                roma_counter--
                pop_mode()
                print_backspace(1)

                ; ローマ字が消えたら母音入力モードに戻す
                if(roma_counter == 0)
                {
                    skk_mode = SKKMODE_INIT
                }

                result_string_ptr = 0
                is_break = true
                return
            }
            ; 既入力文字がない場合はこっち
            result_string[0] = 0
            void strings.append(result_string, backspace_str)
            is_break = true
            result_string_ptr = &result_string
            return
        }

        ; コントロールコードとスペースはそのまま返す
        ; コントロールコード参考
        ; 19: 左
        ; 4 : 右
        ; 5 : 上
        ; 24 : 下
        if(ch <= $20)
        {
            result_string[0] = ch
            result_string[1] = 0
            is_break = true
            result_string_ptr = &result_string
            return
        }

        ; 'L'でローマ字入力モードに遷移する
        if ch == $4c
        {
            skk_mode = SKKMODE_DIRECT
            is_break = true
            return
        }

        ; ここまできたら母音はそのまま返し、子音の場合はSKKMODE_ROMAに遷移する

        ; 該当文字のテーブルを返す(current_table_numは必ず0のはず……)
        uword table = search_chr_table(current_table_num, ch)
        if table == 0
        {
            ; もし前の文字が「n」だったら「ん」を返し、次の文字を入力状態にする
            if current_table_num == 9
            {
                roma_commit_and_next(ch, 70)
                return
            } else if prev_ch == ch
            {
                ; 同じ音が重なった時は「っ」を返す
                roma_commit_and_next(ch, 79)
                return
            }

            ; テーブルに無いのでそのまま返す
            is_break = true
            result_string_ptr = 0
            return
        }

        ; 標準的なローマ字かな変換
        is_break = roma_to_kana(table, ch)
        
        ; ローマ字入力モードに入る
        if result_string_ptr == 0
        {
            skk_mode = SKKMODE_ROMA
        }
    }

    sub roma_to_kana(uword table, ubyte ch) -> bool
    {
        ubyte chlow  = @(table)
        table++
        ubyte chhigh = @(table)
        table++

        if (chlow & (KANA_NEXT as ubyte)) != 0
        {
            ; テーブルを動かす
            push_mode(chhigh)
            ; アルファベット文字のカウンタを増やす
            roma_counter++
            prev_ch = ch
            ; アルファベットを表示する(直接表示でいいかもなあ)
            jtxt.putc(ch)

            result_string_ptr = 0
            return true
        } else {
            ; 確定したかな文字を返す
            print_backspace(roma_counter)
            clear_mode()
            set_table_string(chhigh)
            result_string_ptr = &result_string
            return true
        }
        return false
    }

    sub search_chr_table(ubyte table_idx, ubyte ch) -> uword
    {
        uword table = chr_table[table_idx]

        ; テーブル検索
        repeat {
            ubyte chlow  = @(table)
            table++
            ubyte chhigh = @(table)
            table++

            if (chlow & $7f) == ch
            {
                ; 発見
                table -= 2
                return table
            }
            if chlow == 0 and chhigh == 0
            {
                break
            }
        }

        return 0
    }

    sub roma_commit_and_next(ubyte ch, ubyte idx)
    {
         print_backspace(1)     ; 不要なローマ字を消す
         set_table_string(idx)  ; 確定文字
         clear_mode()

         ; update() で処理するための入力文字
         update_ch = ch

         is_break = true
         if skk_mode < SKKMODE_KANJI
         {
            result_string_ptr = &result_string
         } else {
            result_string_ptr = 0
         }
    }

    sub kanji_input(ubyte ch)
    {
        uword kouho
        ubyte cch = ch & $7f

        if ch == $20
        {
            ; 'n'
            if current_table_num == 9
            {
                set_table_string(70)   ; ん
                void strings.append(kanji_yomigana, result_string)
                roma_counter = 0
            }
            ; 変換キー
             kouho = convert_kanji(kanji_yomigana, false)
             if kouho != 0 {
                current_table_num = 0
                print_backspace(get_string_count(kanji_yomigana) + 1)
                jtxt.print(kanji_henkan_mark)
                jtxt.print(kouho)
             } else {
                current_table_num = 0
                print_backspace(get_string_count(kanji_yomigana))
                jtxt.print(kanji_yomigana)
                is_break = true
                return 
             }
             skk_mode = SKKMODE_KANJI_KOUHO
             is_break = true
             return
        }

        ; 通常入力モードでBackspaceが押されたら $14自体を返す
        if ch == $14
        {
            ; ローマ字が1文字でも入力されている場合はこっち
            if roma_counter > 0
            {
                roma_counter--
                pop_mode()
                print_backspace(1)

                ; ローマ字が消えたら漢字の母音入力モードに戻す
                if(roma_counter == 0)
                {
                    skk_mode = SKKMODE_KANJI
                }

                result_string_ptr = 0
                is_break = true
                return
            }
            print_backspace(1)  ; ▽を消す
            void yomigana_backspace()
            if kanji_yomigana[0] == 0
            {
                ; 既入力文字がない場合は通常モードに戻る
                print_backspace(1)  ; ▽を消す
                skk_mode = SKKMODE_INIT
                result_string[0] = 0
                is_break = true
                result_string_ptr = 0
                return
            }
            is_break = true
            result_string_ptr = 0
            return
        }

        ; 改行の場合は読み仮名で確定してしまう
        if ch == $d
        {
            ubyte bs_count = get_string_count(kanji_yomigana)
            print_backspace(bs_count + 1)

            result_string_ptr = kanji_yomigana
            is_break = true
            skk_mode = SKKMODE_INIT
            return
        }

        uword table = search_chr_table(current_table_num, cch)
        if table == 0
        {
            ; もし前の文字が「n」だったら「ん」を読み仮名に加え、次の文字を入力状態にする
            if current_table_num == 9
            {
                if is_doushi_conv
                {
                    okuri_counter++
                    print_backspace(okuri_counter)
                    roma_commit_and_next(ch, 70)
                    jtxt.print("*")
                    void strings.append(doushi_okuri, result_string)
                    jtxt.print(doushi_okuri)
                    return

                } else {
                    roma_commit_and_next(ch, 70)
                    jtxt.print(result_string)
                    void strings.append(kanji_yomigana, result_string)
                    return
                }
            } else if prev_ch == cch
            {
                if is_doushi_conv
                {
                    okuri_counter++
                    print_backspace(okuri_counter)
                    roma_commit_and_next(cch, 79)
                    jtxt.print("*")
                    void strings.append(doushi_okuri, result_string)
                    jtxt.print(doushi_okuri)
                    return
                } else {
                    ; 同じ音が重なった時は「っ」を返す
                    roma_commit_and_next(cch, 79)
                    jtxt.print(result_string)
                    void strings.append(kanji_yomigana, result_string)
                    return
                }
            }

            ; テーブルに無い
            is_break = true
            result_string_ptr = 0
            return
        }

        if with_shift
        {
            if current_table_num == 0 and is_doushi_conv == false
            {
                jtxt.print("*")
                doushi_okuri[0] = cch | $20
                doushi_okuri[1] = 0
                void strings.append(kanji_yomigana, doushi_okuri)
                doushi_okuri[0] = 0

                ; こうなったら確定まで待つ
                okuri_counter = 0
                is_doushi_conv = true
            }
        }

        is_break = roma_to_kana(table, cch)
        ; 読み仮名の方に足す
        if is_break and result_string_ptr != 0
        {
            ; 動詞変換中の場合ここで候補選択モードに遷移する
            if is_doushi_conv
            {
                jtxt.print(result_string)
                print_backspace(roma_counter + okuri_counter)
                kouho = convert_kanji(kanji_yomigana, true)
               if kouho != 0 {
                   current_table_num = 0
                   print_backspace(get_string_count(kanji_yomigana) + 2)
                   jtxt.print(kanji_henkan_mark)
                   jtxt.print(kouho)
                   if okuri_counter == 0
                   {
                    void strings.copy(result_string, doushi_okuri)
                   } else {
                    void strings.append(doushi_okuri, result_string)
                   }
                   jtxt.print(doushi_okuri)
                   skk_mode = SKKMODE_KANJI_DOUSHI_KOUHO
                   result_string_ptr = 0
                   return
               } else {
                    ; *(読み仮名)を削除
                    print_backspace(2)
                    ; 読み仮名末尾を削除
                    is_doushi_conv = false
                    is_break = true
                    return 
               }
            }

            jtxt.print(result_string)
            void strings.append(kanji_yomigana, result_string)
            result_string_ptr = 0
        } else {
            ; 子音入力に移る
            skk_mode = SKKMODE_KANJI_OKURI
        }
    }

    sub kanji_kouho_input(ubyte ch)
    {
        ubyte bs_count

        bs_count = get_string_count(kouho_ptrs[kouho_index])
        if ch == $20
        {
            kouho_index = (kouho_index + 1) % kouho_count
            print_backspace(bs_count)
            jtxt.print(kouho_ptrs[kouho_index])
            is_break = true
            return
        } else if ch == 'x' or ch == $14
        {
            ; 読み仮名に戻す
            print_backspace(bs_count + 1)
            jtxt.print(kanji_input_mark)
            jtxt.print(kanji_yomigana)
            skk_mode = SKKMODE_KANJI
            is_break = true
            return
        }
        kanji_yomigana[0] = 0

        ; ここまできたら確定して、chを渡す

        ; ▼まで含めて消す
        print_backspace(bs_count + 1)

        if ch != $0a and ch != $d
        {
            update_ch = ch
        }
        result_string_ptr = kouho_ptrs[kouho_index]
        is_break = true
        skk_mode = SKKMODE_INIT
    }

    sub kanji_doushi_kouho(ubyte ch)
    {
        ubyte bs_count
        bs_count = get_string_count(kouho_ptrs[kouho_index]) + 1 + okuri_counter
        if ch == $20
        {
            kouho_index = (kouho_index + 1) % kouho_count
            print_backspace(bs_count)
            jtxt.print(kouho_ptrs[kouho_index])
            jtxt.print(doushi_okuri)
            is_break = true
            return
        } else if ch == 'x' or ch == $14
        {
            ; 読み仮名に戻す
            print_backspace(bs_count + 1)
            jtxt.print(kanji_input_mark)
            void yomigana_backspace()    ; 送り文字を消す
            jtxt.print(kanji_yomigana)
            skk_mode = SKKMODE_KANJI
            current_table_num = 0
            is_doushi_conv = false
            is_break = true
            return
        }
        print_backspace(bs_count + 1)
        if ch != $0a
        {
            update_ch = ch
        }
        void strings.copy(kouho_ptrs[kouho_index], result_string)
        void strings.append(result_string, doushi_okuri)
        result_string_ptr = &result_string
        kanji_yomigana[0] = 0
        roma_counter = 0
        is_doushi_conv = false
        is_break = true
        skk_mode = SKKMODE_INIT
    }

    sub direct_input(ubyte ch)
    {
        ; Ctrl + J で SKKモードに戻る
        if ch == $0a
        {
            skk_mode = SKKMODE_INIT
            is_break = true
            return
        }
        if ch == $14
        {
            ch = $08
        }

        if ch >= $80
        {
            if ch == $ba
            {
                ; {
                ch = $7b
            } else if ch == $c0
            {
                ; }
                ch = $7d
            } else {
                ch = ch & $7f
            }
        } else if ch >= $41 and ch <= $5a {
            ; 大文字を小文字に
            ch = ch | $20
        }

        ; それ以外の場合はそのまま戻す(大丈夫？)
        result_string[0] = ch
        result_string[1] = 0
        result_string_ptr = &result_string
        is_break = true
    }

    sub update() -> uword
    {
        if update_ch != $ff
        {
            uword result = input(update_ch)
            prev_ch = update_ch
            update_ch = $ff
            return result
        }
        return 0
    }

    ubyte first_update

    ; 何か入力したらそのキーコードまたは漢字を返す
    sub process_key_input() -> uword
    {
        repeat
        {
            if getch_mode == GETCHMODE_WAIT
            {
                ubyte keydat
                ubyte keylen
                keydat, keylen = cx16.kbdbuf_peek()
                if keylen != 0
                {
                    ubyte ch
                    bool flag
                    flag, ch = cbm.GETIN()

                    buff_adr = input(ch)
                    if buff_adr != 0
                    {
                        getch_mode = GETCHMODE_SEND_STR
                        first_update = 1
                    } else {
                        buff_adr = update()
                        if buff_adr != 0
                        {
                            getch_mode = GETCHMODE_SEND_STR
                            first_update = 1
                        }
                    }
                }
            } else if getch_mode == GETCHMODE_SEND_STR
            {
                ; buff_adrから1文字ずつ送り出す
                uword wch = @(buff_adr)
                if wch == 0
                {
                    first_update = 0
                    buff_adr = update();
                    if buff_adr == 0
                    {
                        getch_mode = GETCHMODE_WAIT
                    }
                    continue
                }
                buff_adr++
                if wch < $7f or (wch >= $a1 and wch <= $df)
                {
                    ; 半角文字またはコントロールコードの場合はそのまま返す
                    return wch
                } else {
                    ; 全角文字のはずなので2バイトぶん拾って返す(大丈夫かな)
                    wch = (wch << 8) | @(buff_adr)
                    buff_adr++
                    return wch
                }
            }
        }
    }
}