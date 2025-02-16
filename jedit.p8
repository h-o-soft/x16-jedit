%import textio
%import diskio
%import palette
%import jtxt
%import tinyskk
%import bmem

%zeropage basicsafe
;%option no_sysinit


; 
; だいぶシンプルな日本語エディタ
; 
; ※メモリチェックまわりが甘いのであまり本気で使わないでください
jedit {
    const ubyte VLINE_MAX = 19
    const ubyte LINE_MAX = 255
    const ubyte TXT_ROW = 28

    ; カーソル位置(world)
    ubyte curx
    ubyte cury
    ; 横方向の表示オフセット位置
    ubyte ox
    ; 縦方向の表示オフセット位置
    ubyte oy

    ; 画面上のカーソル位置
    ubyte lcurx
    ubyte lcury

    uword line_max = 0

    ; インサートモードかどうか
    bool is_insert_mode = false

    ubyte work_bank
    ; ラインバッファは128文字までに制限する
    uword[128] @nosplit line_buffer
    ubyte line_buffer_size = 0

    ubyte[255] fname
    bool is_dirty = false

    ubyte[255] temp_buffer

    uword[128] @nosplit line_copy_buffer

    sub update_curpos() -> bool
    {
        bool result = false
        word x = curx as word - ox as word
        if x < 0
        {
            ; 画面左端戻る
            ox = curx
            lcurx = 0
            result = true
        } else if x > 39
        {
            ; 画面右端へ
            ox = curx - 39
            lcurx = 39
            result = true
        } else {
            lcurx = lsb(x)
        }
        jtxt.locate(lcurx, lcury)

        ; 最大行数を更新しておく
        if line_max < cury
        {
            line_max = cury
        }

        return result
    }

    sub initialize(ubyte bank)
    {
        work_bank = bank
        curx = 0
        lcurx = 0
        cury = 0
        lcury = 0
        ox = 0
        oy = 0

        jtxt.init(bank);
        jtxt.set_range(0,240-12)
        txt.color2(7,0)

        txt.print("loading font...")
        if jtxt.load_font("jfont.bin") == 0
        {
            cbm.CINT();
            txt.nl()
            txt.print("font load error.")
        }
        txt.print("done.")
        txt.nl()
        txt.print("loading dictionary...")
        if tskk.load_dic("skkdicm.bin", bank + 15) == 0
        {
            cbm.CINT();
            txt.nl()
            txt.print("dictionary load error.")
        }
        txt.print("done.")
        txt.nl()
        ; Bank: 1 〜 15 = font
        ; Bank: 16 〜 text
        ; 64Bankあるので、その中でやりくりする事……

        ; 128kバイトのバンクRAMを確保、256行分のバッファを確保
        if bmem.init(33 + bank, 128/8, LINE_MAX) != 0
        {
            cbm.CINT();
            txt.nl()
            txt.print("memory allocation error.")
        }

        ; ラインバッファをクリア
        line_buffer[0] = 0
        line_buffer_size = 0

        cx16.rambank(33 + bank)

        clear_text()
    }

    sub clear_text()
    {
        txt.clear_screen()
        txt.column(0)
        txt.row(TXT_ROW + 1)
        txt.print("   ^r: open file    ^x: exit")
    }

    sub proc_backspace()
    {
        ubyte cidx
        if curx > 0 and curx <= line_buffer_size
        {
            curx--
            ubyte i
            for i in curx to line_buffer_size-1
            {
                line_buffer[i] = line_buffer[i+1]
            }
            line_buffer_size--
            update_proc()
            is_dirty = true
        } else if curx == 0
        {
            ; 前の行とつなげる
            if cury > 0
            {
                ; 現在バッファをコピーしておく
                uword ccnt = line_buffer_size
                for cidx in 0 to line_buffer_size
                {
                    line_copy_buffer[cidx] = line_buffer[cidx]
                }
                bmem.move_handle(cury, line_max - cury, false)
                cury--
                line_max--
                bmem.get_mem(cury, &line_buffer, 256)
                update_line_buffer_size()
                curx = line_buffer_size
                ; change_line(-1)
                ; 現在の行にline_copy_bufferをつなげる
                ccnt += line_buffer_size
                if ccnt > 127
                {
                    ccnt = 127
                }
                for cidx in line_buffer_size to (ccnt as ubyte)
                {
                    line_buffer[cidx] = line_copy_buffer[cidx-line_buffer_size]
                }
                update_line_buffer_size()
                bmem.set_mem(cury, &line_buffer, 256)
                void change_line(0)
                all_redraw()
                void update_curpos()
                is_dirty = true
            }
        }
    }

    sub proc_enter()
    {
        ubyte cidx

        if(cury >= LINE_MAX)
        {
            ; 最大行サイズ以上には改行出来ない
            return
        }
        bool redraw = ox != 0

        ; 挿入モードでは一行追加
        if is_insert_mode {
            is_dirty = true
            ; 行の分離をする
            if curx < line_buffer_size
            {
                ; カーソル位置より右側を次の行に移動
                ; line_copy_bufferに右側を保存
                for cidx in curx to line_buffer_size-1
                {
                    line_copy_buffer[cidx - curx] = line_buffer[cidx]
                }
                line_copy_buffer[line_buffer_size - curx] = 0

                ; 現在行の右側を消す
                line_buffer[curx] = 0
                line_buffer_size = curx
            } else {
                line_copy_buffer[0] = 0
            }
            void change_line(1)
            ; curyからline_maxまでを1行ずつ下にずらす
            ; cury ->  cury+1 を、カウント数ぶんだけ繰り返す
            ; curyについては最終的にはfreeする
            bmem.move_handle(cury, line_max - cury, true)
            ; line_copy_bufferを新しい行として設定
            for cidx in 0 to 127
            {
                line_buffer[cidx] = line_copy_buffer[cidx]
            }
            update_line_buffer_size()
            bmem.set_mem(cury, &line_buffer, 256)

            line_max++
            redraw = true
        } else {
            redraw = change_line(1)
        }
        curx = 0
        ox = 0
        if redraw {
            all_redraw()
        }
        void update_curpos()
    }

    sub proc_control_code(uword ch)
    {
        ; カーソル移動
        if ch == 19
        {
            ; カーソル左
            if curx > 0
            {
                curx--
                update_proc()
            }
        } else if ch == 29
        {
            ; カーソル右
            if curx < line_buffer_size
            {
                curx++
                update_proc()
            }
        } else if ch == $0f
        {
            ; ^o インサートモード切り替え
            is_insert_mode = not is_insert_mode
        } else if ch == $08
        {
            ; ^h バックスペース
            proc_backspace();
        } else if ch == $05
        { 
            ; ↑上カーソル
            if cury == 0
            {
                return
            }
            void change_line(-1)
        } else if ch == 17 ; $18
        { 
            ; ↑下カーソル
            if cury >= line_max 
            {
                return
            }
            void change_line(1)
        } else if ch == $0d
        {
            ; 改行
            proc_enter();
        } else if ch == $12
        {
            ; Ctrl + R (Read File)
            void check_save()
            if set_filename(true)
            {
                load()
            }
        } else if ch == 24
        {
            ; Ctrl + X (Save or Exit)
            if check_save()
            {
                app_exit()
            } else {
                if check_yesno("force exit? (y/n)")
                {
                    app_exit()
                }
            }
            clear_text()
        } else {
            ; txt.print_uwhex(ch, false)
            ; txt.nl()
        }
    }

    sub proc()
    {
        repeat {
            ; 1文字入力を待つ(入力なしの場合0の方がいいかなー)
            uword ch = tskk.process_key_input()

            ; コントロールコード？
            if ch < $20
            {
                proc_control_code(ch);
            } else {
                ; 文字なのでラインバッファに追加
                update_linebuffer(ch)
                is_dirty = true
            }
        }
    }

    sub app_exit()
    {
        void jtxt.restore_screen_mode();
        sys.exit(0)
    }

    sub check_save() -> bool
    {
        if is_dirty
        {
            if check_yesno("save before exit? (y/n)")
            {
                if set_filename(false)
                {
                    txt.nl()
                    txt.print(fname)
                    txt.nl()
                    return save()
                }
                return true
            } else {
                clear_text()
            }
        } else {
            return true
        }
        return false
    }

    sub set_txthome()
    {
        txt.column(0)
        txt.row(TXT_ROW)
    }

    str PETSCII_TABLE = "@abcdefghijklmnopqrstuvwxyz[\\].. !\"#$%&'()*+,-./0123456789:;<=>?-ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    sub set_filename(bool is_open) -> bool
    {
        clear_text()
        set_txthome()
        if is_open
        {
            txt.print("open")
        } else {
            txt.print("save")
        }
        txt.print(" file name: ")
        txt.print(fname)
        void txt.input_chars(fname)

        ubyte col
        ubyte cidx = 0
        for col in 16 to 40
        {
            ubyte ch = txt.getchr(col, TXT_ROW)
            if ch == 32
            {
                break
            } else if ch < 90
            {
                fname[cidx] = PETSCII_TABLE[ch]
            }
            cidx++
        }
        fname[cidx] = 0
        clear_text()
        return cidx > 0
    }

    sub check_yesno(str msg) -> bool
    {
        clear_text()
        set_txthome()
        txt.print(msg)
        repeat
        {
            ubyte ch = cbm.GETIN2()
            if ch == 'y'
            {
                return true
            } else if ch == 'n'
            {
                return false
            }
        }
    }

    ; ShiftJISの一文字目か？
    sub is_multibyte(uword ch) -> bool
    {
        return ((ch >= $81 and ch <= $9F) or (ch >= $E0 and ch <= $EF))
    }

    sub load()
    {
        if diskio.f_open(fname) {
            uword ch
            ubyte cidx = 0
            cury = 0
            do {
                uword sz = diskio.f_read(&ch, 1)
                if sz == 0
                {
                    line_buffer[cidx] = 0
                    bmem.set_mem(cury, &line_buffer, (cidx + 1) * 2)
                    break
                } else if ch == $0a 
                {
                    goto load_linecommit
                } else if ch == $0d
                {
                    ; CRは無視
                } else {
                    if is_multibyte(ch)
                    {
                        ch = ch << 8
                        void diskio.f_read(&ch, 1)
                    }
                    line_buffer[cidx] = ch
                    ch = 0
                    cidx++
                    if cidx >= 127
                    {
                        goto load_linecommit
                    }
                }
                goto load_cont
load_linecommit:
                line_buffer[cidx] = 0
                bmem.set_mem(cury, &line_buffer, (cidx + 1) * 2)
                cury++
                if cury >= LINE_MAX
                {
                    break
                }
                cidx = 0
load_cont:
            } until sz == 0
            diskio.f_close()

            line_max = cury
            cury = 0
            lcury = 0
            oy = 0
            ox = 0
            curx = 0
            lcurx = 0
            all_redraw()
            bmem.get_mem(cury, &line_buffer, 256)
            update_line_buffer_size()
        } else {
            fname[0] = 0
        }
        is_dirty = false
    }

    sub save() -> bool
    {
        void change_line(0)
        if fname[0] != '@'
        {
            void strings.copy(fname, temp_buffer)
            fname[0] = '@'
            fname[1] = ':'
            fname[2] = 0
            void strings.append(fname, temp_buffer)
        }
        if diskio.f_open_w(fname) {
            if diskio.status_code() == 255
            {
                return false
            }
            uword i
            for i in 0 to line_max
            {
                bmem.get_mem(i, &line_buffer, 256)
                ubyte cidx = 0
                ubyte ch_msb
                ubyte ch_lsb
                for cidx in 0 to 127
                {
                    uword  ch = line_buffer[cidx]
                    ch_lsb = lsb(ch)
                    ch_msb = msb(ch)
                    if ch == 0
                    {
                        break
                    } else if ch_msb == 0
                    {
                        void diskio.f_write(&ch, 1)
                    } else {
                        void diskio.f_write(&ch_msb, 1)
                        void diskio.f_write(&ch_lsb, 1)
                    }
                }
                ; 改行コードを書く(LFのみ)
                if i < line_max
                {
                    void diskio.f_write("\x0a", 1)
                }
            }
            diskio.f_close_w()
            is_dirty = false
            return true
        }
        return false
    }

    sub change_line(byte addy) -> bool
    {
        ; 現在のバッファを反映
        bmem.set_mem(cury, &line_buffer, line_buffer_size * 2 + 2)
        cury = cury + (addy as ubyte)
        bmem.get_mem(cury, &line_buffer, 256)
        update_line_buffer_size()

        bool is_redraw = false
        ; 画面外にハミ出した場合はoyを補正する
        if cury < oy
        {
            oy = cury
            is_redraw = true
        } else if cury >= oy + VLINE_MAX
        {
            oy = cury - VLINE_MAX + 1
            is_redraw = true
        }
        lcury = cury - oy

        ; で、描く
        if is_redraw
        {
            if addy > 0
            {
                jtxt.scroll_up()
                ;jtxt.clear_endline()
                disp_line(lcury)
            } else if addy < 0
            {
                jtxt.scroll_down()
                disp_line(lcury)
            } else {
                ubyte i
                for i in 0 to VLINE_MAX-1
                {
                    bmem.get_mem(oy + i, &line_buffer, 256)
                    jtxt.locate(0, i)
                    jtxt.wprint(line_buffer)
                }
            }
            ; TODO どうにかする(どうにかとは……)
            bmem.get_mem(cury, &line_buffer, 256)
            update_line_buffer_size()
        }

        jtxt.locate(lcurx, lcury)
        return update_curpos()
    }

    sub update_line_buffer_size()
    {
        ubyte i
        for i in 0 to 127
        {
            if line_buffer[i] == 0
            {
                line_buffer_size = i
                return
            }
        }
        line_buffer_size = 127
    }

    sub update_linebuffer(uword ch)
    {
        ubyte i
        bool update_line = false
        ; もしカーソル位置より左にラインバッファの末尾がある場合は空白で埋める
        if line_buffer_size <= curx
        {
            if curx > 0
            {
                for i in line_buffer_size to (curx as ubyte)-1
                {
                    line_buffer[i] = $20    ; ' '
                }
            }
            line_buffer[curx] = ch
            curx++
            line_buffer[curx] = 0
            line_buffer_size = curx
            void jtxt.putc_draw(ch)
        } else if is_insert_mode
        {
            ; curxの位置に挿入する
            ; まずはコピー(0まで含め)
            for i in line_buffer_size downto curx
            {
                line_buffer[i+1] = line_buffer[i]
            }
            line_buffer[curx] = ch
            curx++
            line_buffer_size++
            update_line = true
            ; その上で描きなおす(仮)
        } else {
            ; 上書きモードの場合は普通に上書きするだけ
            line_buffer[curx] = ch
            jtxt.putc(ch)
            curx++
        }

        update_proc()
    }

    sub disp_line(ubyte ly)
    {
        uword lofs = oy + ly
        bmem.get_mem(lofs, &line_buffer, 256)
        update_line_buffer_size()
        jtxt.locate(0, ly)

        byte disp_cnt = (line_buffer_size - ox) as byte
        if disp_cnt > 40
        {
            disp_cnt = 40
        } else if disp_cnt < 0
        {
            disp_cnt = 0
        }
        if disp_cnt > 0
        {
            jtxt.nwprint(&line_buffer + ox * 2, disp_cnt as ubyte)
        }
        if disp_cnt < 40
        {
            disp_cnt = 40 - disp_cnt
            ubyte j
            for j in 0 to (disp_cnt as ubyte)-1
            {
                jtxt.putc_space()
                jtxt.tx++
            }
        }
    }

    sub all_redraw()
    {
        ubyte i
        for i in 0 to VLINE_MAX-1
        {
            disp_line(i)
        }
        bmem.get_mem(cury, &line_buffer, 256)
        update_line_buffer_size()
        jtxt.locate(lcurx, lcury)
    }

    sub update_proc()
    {
        ubyte i
        bool cupdate = update_curpos()

        if cupdate
        {
            ; バッファ反映……
            void change_line(0)
            ; 全描画しなおしが必要なはず
            all_redraw()
            return
        }


        ; 一行描画
        jtxt.locate(0, lcury)
        byte disp_cnt = (line_buffer_size - ox) as byte
        if disp_cnt > 40
        {
            disp_cnt = 40
        }
        jtxt.nwprint(&line_buffer + ox * 2, disp_cnt as ubyte)
        jtxt.cx = $80

        ; 行末から最終行まで空白を埋める(要最適化)
        if disp_cnt < 40
        {
            disp_cnt = 40 - disp_cnt
            for i in 0 to (disp_cnt as ubyte)-1
            {
                void jtxt.putc_draw($20)
                jtxt.tx++
            }
        }
        ; txt.nl()
        jtxt.locate(lcurx, lcury)
    }
}

main {
    sub start()
    {
        jedit.initialize(1)
        jedit.proc()
    }
}
