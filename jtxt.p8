
%option ignore_unused

jtxt {
    ubyte tx
    ubyte ty
    ubyte top_y
    ubyte bottom_y
    ubyte line_count = 20
    ubyte cx
    ubyte cy

    ubyte system_screen_mode
    ubyte txt_bank
    ubyte font_bank

    sub init(ubyte bank)
    {
        ; Layer 0 only / 1bpp bitmap mode
        system_screen_mode, tx, ty = cx16.get_screen_mode()
        void cx16.set_screen_mode($80)

        cx16.VERA_DC_HSCALE = 64
        cx16.VERA_DC_VSCALE = 64
        cx16.VERA_L0_CONFIG = 4
        cx16.VERA_L0_TILEBASE = (cx16.VERA_L0_TILEBASE & $FC) + 0

        ; background color is dark blue...
        palette.set_color(0, $0a)
        ; text color to white?
        cx16.VERA_L0_HSCROLL_H = 0

        tx = 0
        ty = 0
        cx = $80 

        ; 画面の範囲を設定(実験)
        ; set_range(5, 240-5)
        set_range(0, 240)

        txt_bank = bank
        font_bank = bank+1
        screen_clear(true)
    }

    sub load_font(str fname_ptr) -> uword
    {
        cx16.rambank(font_bank)
        return diskio.load_raw(fname_ptr, $a000)
    }

    sub set_range(ubyte top, ubyte bottom)
    {
        top_y = top
        bottom_y = bottom

        line_count = (bottom_y - top_y) / 12
    }

    sub screen_clear(bool vramclear)
    {
        uword adr = top_y * 40
        cx16.VERA_ADDR_L = lsb(adr)
        cx16.VERA_ADDR_M = msb(adr)
        cx16.VERA_ADDR_H = (1 << 4) | 0
        uword @zp i = 0
        uword yrange = bottom_y - top_y
        for i in 0 to yrange * 40 - 1 {
            cx16.VERA_DATA0 = $0
        }
        tx = 0
        ty = 0
        cx = $80 

        if vramclear
        {
            ; txt_bankの先頭が仮想日本語テキストVRAMになる
            ; ubyte bank_backup = cx16.getrambank()
            cx16.rambank(txt_bank)
            sys.memset($a000, 40*25*2, 0)
            ; cx16.rambank(bank_backup)
        }
        disp_cursor()
    }

    sub clear_endline()
    {
        uword adr = tx + ty * 480 + top_y * 40
        ubyte ccnt = 40 - tx
        repeat ccnt
        {
            cx16.VERA_ADDR_L = lsb(adr)
            cx16.VERA_ADDR_M = msb(adr)
            cx16.VERA_ADDR_H = (11 << 4) | 0
            repeat 12
            {
                cx16.VERA_DATA0 = $0
            }
            adr++
        }

        ; 最下行を0でクリア
        cx16.rambank(txt_bank)
        sys.memset($a000 + ((line_count as uword)-1)*80, 40*2, 0)
    }

    sub scroll_up()
    {
        ; dst / ADDRSEL = 0
        uword dstadr = top_y * 40
        cx16.VERA_CTRL = 0
        cx16.VERA_ADDR_L = lsb(dstadr)
        cx16.VERA_ADDR_M = msb(dstadr)
        cx16.VERA_ADDR_H = (1 << 4) | 0
        ; source / ADDRSEL = 1
        dstadr = dstadr + 480
        cx16.VERA_CTRL = 1
        cx16.VERA_ADDR_L = lsb(dstadr)
        cx16.VERA_ADDR_M = msb(dstadr) 
        cx16.VERA_ADDR_H = (1 << 4) | 0

        ; 1 line scroll up
        repeat 480*(line_count - 1)
        {
            cx16.VERA_DATA0 = cx16.VERA_DATA1
        }
        cx16.VERA_CTRL = 0

        ; text vramもスクロール
        cx16.rambank(txt_bank)
        ; sys.memcopyがなぜか動かないようだったので自力で対応( bug? )
        ; sys.memcopy($a000 + 40 * 2, $a000, ((line_count as uword))*80)
        uword i
        for i in 0 to ((line_count as uword)-1)*80
        {
            @(i + $a000) = @(i + $a000 + 40*2)
        }

        ; カーソルを上に上げる(上げなくていいのかも)
        cy--
        if (cy & $80) != 0
        {
            cx = $80 
        }
    }

    sub scroll_down()
    {
        ; dst / ADDRSEL = 0
        uword dstadr = top_y * 40 + line_count * 480
        cx16.VERA_CTRL = 0
        cx16.VERA_ADDR_L = lsb(dstadr)
        cx16.VERA_ADDR_M = msb(dstadr)
        cx16.VERA_ADDR_H = (1 << 4) | $8
        ; source / ADDRSEL = 1
        dstadr = dstadr - 480
        cx16.VERA_CTRL = 1
        cx16.VERA_ADDR_L = lsb(dstadr)
        cx16.VERA_ADDR_M = msb(dstadr) 
        cx16.VERA_ADDR_H = (1 << 4) | $8

        ; 1 line scroll down
        repeat 480*(line_count - 1)
        {
            cx16.VERA_DATA0 = cx16.VERA_DATA1
        }
        cx16.VERA_CTRL = 0

        ; text vramもスクロール
        cx16.rambank(txt_bank)
        uword i
        for i in ((line_count as uword)-2)*80 downto 0
        {
            @(i + $a000 + 40*2) = @(i + $a000)
        }
        ; sys.memcopy($a000 + 40 * 2, $a000, 18*80)

        ; ; カーソルを下に下げる(下げなくていいのかも)
        cy++
        if cy >= line_count
        {
            cx = $80 
        }
    }

    sub wprint(uword sptr)
    {
        ; 1文字1uwordで0まで表示
        repeat
        {
            uword ch = @(sptr)
            ch = ch | ((@(sptr+1) as uword) << 8)
            if ch == 0
            {
                break
            }
            putc(ch)
            sptr += 2
        }
    }

    sub nwprint(uword sptr, ubyte clen)
    {
        while clen != 0
        {
            uword ch = @(sptr)
            ch = ch | ((@(sptr+1) as uword) << 8)
            if ch == 0
            {
                break
            }
            void putc_draw(ch)
            tx++
            if tx >= 40
            {
                tx = 0
                ty++
                if ty >= line_count
                {
                    ty = line_count-1
                    scroll_up()
                    clear_endline();
                }
            }
            sptr += 2
            clen--
        }
        ;cx = $80
        ;disp_cursor()
    }

    sub print(uword sptr)
    {
        uword @zp ch;
        uword @zp ch2;
        ubyte bank_backup = cx16.getrambank();
        ubyte current_bank = bank_backup
        repeat
        {
            ch = @(sptr);
            if ch == 0
            {
                break;
            }
            if not (ch <= $7f or (ch >= $a1 and ch <= $df))
            {
                ; 全角文字である
                sptr++
                if sptr == $c000
                {
                    sptr = $a000
                    current_bank++;
                    cx16.rambank(current_bank);
                }
                ch2 = @(sptr)
                ch = (ch << 8) | ch2
            }
            putc(ch)
            sptr++
            if sptr == $c000
            {
                sptr = $a000
                current_bank++;
                cx16.rambank(current_bank);
            }
        }
        cx16.rambank(bank_backup);
    }

    ; 1文字出力
    ; 下位が1バイト目、上位が2バイト目
    ; 1バイト文字の場合は上位は0になっている
    sub putc(uword chw)
    {
        ubyte bank_backup = cx16.getrambank()
        if putc_draw(chw)
        {
            tx++;
            if tx >= 40
            {
                tx = 0;
                ty++;
                if ty >= line_count
                {
                    ty = line_count-1
                    scroll_up()
                    clear_endline();
                }
            }
        }
        disp_cursor()

        cx16.rambank(bank_backup);
    }

    sub putc_space()
    {
        ubyte[12] font = [0,0,0,0,0,0,0,0,0,0,0,0]
        drawc(&font);
        cx16.rambank(txt_bank)
        uword vramadr = $a000
        vramadr += (tx as uword) * 2
        vramadr += (ty as uword) * 80
        @(vramadr) = $20
        vramadr++
        @(vramadr) = 0
    }

    ; putcの描画のみ(カーソルを動かさない)
    sub putc_draw(uword chw) -> bool
    {
        uword @zp ch = msb(chw)
        uword @zp ch2 = lsb(chw)
        uword code = $ffff
        ubyte cx16_bank
        if chw == 0
        {
            return false
        }
        if chw <= $7f or (chw >= $a1 and chw <= $df)
        {
            if ch2 == $0a or ch2 == $0d
            {
                tx = 0;
                ty++;
                if ty >= line_count
                {
                    ty = line_count-1;
                    scroll_up()
                    clear_endline();
                }
                code = $ffff

                return false
            } else if ch2 == $08
            {
                backspace()
                code = $ffff
            } else if chw == 5
            {
                ; カーソル上
                if ty > 0
                {
                    ty--
                }
                return false
            } else if chw == 24
            {
                ; カーソル下
                if ty < line_count-1
                {
                    ty++
                }
                return false
            } else if chw == 19
            {
                ; カーソル左
                if tx > 0
                {
                    tx--
                }
                return false
            } else if chw == 4
            {
                ; カーソル右
                if tx < 39
                {
                    tx++
                }
                return false
            } else {
                ; これなんだっけ？
                code = (ch2 as uword) * 12
                cx16_bank = font_bank
            }
        } else {
            ; ShiftJIS -> Ku/Ten
            if ch <= $9f
            {
                if ch2 < $9f
                {
                    ch = (ch << 1) - $102;
                }
                else
                {
                    ch = (ch << 1) - $101;
                }
            }
            else
            {
                if ch2 < $9f
                {
                    ch = (ch << 1) - $182;
                }
                else
                {
                    ch = (ch << 1) - $181;
                }
            }

            if ch2 < $7f
            {
                ch2 -= $40;
            } else if ch2 < $9f
            {
                ch2 -= $41;
            } else {
                ch2 -= $9f;
            }
            code = ch * 94 + ch2;

            uword font_index_offset = 3072;
            ubyte bank = 0
            if code > 5205
            {
                bank = 1
                code -= 5206
                font_index_offset = 8
            }
            code = code * 12 + font_index_offset
            cx16_bank = lsb(font_bank + (((code >> 13) | (bank << 3))))
            code = code & $1fff;
        }
        if code != $ffff
        {
            cx16.rambank(cx16_bank);
            ubyte[12] font;
            if code > $2000-12
            {
                ; code+12が8192以上の値の場合、8192以内のメモリのコピーを行った後に、バンクを1つ上げて、残りをコピーする
                ubyte remain = lsb(8192-code);
                cx16.memory_copy($a000 + code, font, remain);
                cx16.rambank(cx16_bank+1);
                cx16.memory_copy($a000, &font + remain, 12 - remain);
            } else {
                cx16.memory_copy($a000 + code, font, 12);
            }
            drawc(&font);

            ; 仮想VRAMにも書き込む
            cx16.rambank(txt_bank)
            ; uword vramadr = $a000 + (tx + ty * 40)*2
            uword vramadr = $a000
            vramadr += (tx as uword) * 2
            vramadr += (ty as uword) * 80
            @(vramadr) = lsb(chw)
            vramadr++
            @(vramadr) = msb(chw)
            return true
        }
        return false
    }

    ; フォントデータを現在位置に描画する
    sub drawc(uword font_ptr)
    {
        uword @zp i = 0
        uword adr = tx + ty * 480 + top_y * 40
        cx16.VERA_ADDR_L = lsb(adr);
        cx16.VERA_ADDR_M = msb(adr);
        cx16.VERA_ADDR_H = (11 << 4) | 0
        for i in 0 to 11
        {
            cx16.VERA_DATA0 = font_ptr[i]
        }
    }

    sub backspace()
    {
        uword adr
        if tx > 0
        {
            tx--;
            adr = tx + ty * 480 + top_y * 40
            cx16.VERA_ADDR_L = lsb(adr);
            cx16.VERA_ADDR_M = msb(adr);
            cx16.VERA_ADDR_H = (11 << 4) | 0
            repeat 12
            {
                cx16.VERA_DATA0 = $0
            }
        } else {
            if ty > 0
            {
                ty--;
                tx = 39;
                adr = tx + ty * 480 + top_y * 40
                cx16.VERA_ADDR_L = lsb(adr);
                cx16.VERA_ADDR_M = msb(adr);
                cx16.VERA_ADDR_H = (11 << 4) | 0
                repeat 12
                {
                    cx16.VERA_DATA0 = $0
                }
            }
        }
        ; 仮想VRAMの方も消す
        cx16.rambank(txt_bank)
        uword vramadr = $a000
        vramadr += (tx as uword) * 2
        vramadr += (ty as uword) * 80
        @(vramadr) = 32 ; space
        vramadr++
        @(vramadr) = 0

        ;disp_cursor()
    }

    sub restore_screen_mode() -> bool
    {
        return cx16.set_screen_mode(system_screen_mode)
    }

    sub locate(ubyte x, ubyte y)
    {
        tx = x
        ty = y
        disp_cursor()
    }

    sub disp_cursor()
    {
        ubyte tx_bk = tx
        ubyte ty_bk = ty

        ; 動いてない場合は何もしない
        if cx == tx and cy == ty
        {
            return
        }
        cx16.rambank(txt_bank)
        ; 前にカーソル描画していた場合その文字を描画しなおす
        if (cx & $80) == 0
        {
            tx = cx
            ty = cy
            uword addr = $a000
            addr += (tx as uword) * 2
            addr += (ty as uword) * 80
            uword ch = @(addr)
            addr++
            ch = ch | ((@(addr) as uword) << 8)
            if ch == 0 ch = 32
            void putc_draw(ch)
        }
        cx = tx_bk
        cy = ty_bk
        invert(cx, cy)

        ; カーソル位置を戻す
        tx = tx_bk
        ty = ty_bk
    }

    sub invert(ubyte x, ubyte y)
    {
        uword adr = x + y * 480 + top_y * 40
        ; 該当位置から縦12バイトを反転
        cx16.VERA_CTRL = 0
        ; DATA0 -> write
        cx16.VERA_ADDR_L = lsb(adr)
        cx16.VERA_ADDR_M = msb(adr)
        cx16.VERA_ADDR_H = (11 << 4) | 0
        cx16.VERA_CTRL = 1
        ; DATA1 -> read
        cx16.VERA_ADDR_L = lsb(adr)
        cx16.VERA_ADDR_M = msb(adr)
        cx16.VERA_ADDR_H = (11 << 4) | 0
        cx16.VERA_CTRL = 0
        ubyte i
        for i in 0 to 11
        {
            cx16.VERA_DATA0 = cx16.VERA_DATA1 ^ $ff
        }
    }

    ; お試しの全再描画
    sub redraw()
    {
        ubyte tx_bk = tx
        ubyte ty_bk = ty

        screen_clear(false)
        ubyte bank_backup = cx16.getrambank()
        cx16.rambank(txt_bank)
        uword adr = $a000
        uword i
        tx = 0
        ty = 0
        uword drawcnt = 40 * (line_count as uword) - 1
        for i in 0 to drawcnt
        {
            cx16.rambank(txt_bank)
            uword code = @(adr)
            adr++
            code = code | ((@(adr) as uword) << 8)
            adr++
            if code == 0
            {
                code = 32
            }
            void putc_draw(code)
            tx++
            if tx >= 40
            {
                tx = 0
                ty++
            }
        }

        tx = tx_bk
        ty = ty_bk

        cx16.rambank(bank_backup)
    }
}