
; Commander X16 Bank Memory Manager
;  ※そんな大層なものではない。重い。
;  
; * init()で利用するバンクメモリ先頭と、利用バンク数、メモリハンドル個数を指定
; * mallocっぽく使いたい場合
;   * set_mem()で指定ハンドルに対して指定アドレスの内容を指定サイズ書き込む
;   * get_mem()で指定ハンドルのメモリ内容を指定アドレスに読み込む
; * ファイルっぽく使いたい場合(検証甘い)
;   * alloc()で確保する
;   * open()で指定ハンドルを開く
;   * write() で書いたり read() で読んだり seek() で位置を移動したりする

%option ignore_unused

bmem {
    ; メモリ管理領域のサイズ
    ; 3 -> 同時に1メモリしか開けない
    ; 6 -> 同時に複数メモリを開ける
    const ubyte MEM_MAN_SIZE = 6

    ubyte bank_top
    ubyte bank_size
    uword handle_size
    uword data_top

    ; 現在アクセスしているバンク
    ubyte bank_cur
    ; 現在アクセスしているアドレス
    uword addr_cur

    ubyte mem_info
    uword mem_size
    ubyte mem_bank_size

    sub init(ubyte bank, ubyte sz, uword alloc_count) -> ubyte
    {
        if alloc_count * MEM_MAN_SIZE >= $2000
        {
            ; error
            return $80
        }
        ubyte bank_backup = cx16.getrambank()

        bank_top = bank
        bank_size = sz
        handle_size = alloc_count

        ; Initialize bank memory
        cx16.rambank(bank)

        ; Initialize handle area
        uword i
        for i in 0 to (alloc_count*MEM_MAN_SIZE)-1
        {
            @($a000 + i) = 0
        }

        ; Initialize free area
        ; 使用バンク数からハンドル管理領域 & メモリ管理領域4バイトを抜いたサイズを計算
        uword datasize = 8192 - alloc_count*MEM_MAN_SIZE - 4
        data_top = $a000 + alloc_count*MEM_MAN_SIZE

        set_address(bank, data_top)
        put_byte($40)   ; 未使用、終端
        put_byte(lsb(datasize))
        put_byte(msb(datasize))
        put_byte(sz - 1)

        cx16.rambank(bank_backup)
        return 0
    }

    sub set_address(ubyte bank, uword addr)
    {
        bank_cur = bank
        addr_cur = addr
        cx16.rambank(bank_cur)
    }

    sub add_addr()
    {
        addr_cur = addr_cur + 1
        if addr_cur >= $c000
        {
            addr_cur = addr_cur - $2000
            bank_cur = bank_cur + 1
            cx16.rambank(bank_cur)
        }
    }

    sub put_byte(ubyte data)
    {
        @(addr_cur) = data
        add_addr()
    }

    sub get_byte() -> ubyte
    {
        ubyte data = @(addr_cur)
        add_addr()
        return data
    }

    ; 現在のメモリアクセス位置にbank、addrを加算する
    ; バンクが変わった場合は切り替える
    sub add_address(ubyte bank, uword addr)
    {
        addr_cur = addr_cur + addr
        while addr_cur >= $c000
        {
            addr_cur = addr_cur - $2000
            bank_cur = bank_cur + 1
        }
        bank_cur = bank_cur + bank
        cx16.rambank(bank_cur)
    }

    ; 現在のメモリアクセス位置からbank、addrを減算する
    ; バンクが変わった場合は切り替える
    sub sub_address(ubyte bank, uword addr)
    {
        addr_cur = addr_cur - addr
        while addr_cur < $a000
        {
            addr_cur = addr_cur + $2000
            bank_cur = bank_cur - 1
        }
        bank_cur = bank_cur - bank
        cx16.rambank(bank_cur)
    }

    sub search_free(ubyte cxbank, uword cxsize) -> bool
    {
        ; データ領域の先頭から探す
        set_address(bank_top, data_top)

        repeat
        {
            mem_info = get_byte()
            mem_size = get_byte()
            mem_size = mem_size + ((get_byte() as uword) << 8)
            mem_bank_size = get_byte()

            if (mem_info & $80) != 0
            {
                ; 使用中の場合は次に進む
                add_address(mem_bank_size, mem_size)
            } else if mem_bank_size > cxbank or (mem_bank_size == cxbank and mem_size >= cxsize)
            {
                ; 空き領域が見つかった
                ; 管理領域の先頭までアドレスを戻して返る
                sub_address(0, 4)
                return true
            } else if (mem_info & $40) != 0
            {
                ; 終端に到達したので終了(見つからなかった)
                return false
            } else {
                ; 空き領域ではあるが、サイズが足りないので次に進む
                add_address(mem_bank_size, mem_size)
            }
        }
    }

    ; size_lmを下位16ビット、size_hを上位8ビットとしたサイズのメモリを確保する(つまり64KB以上取れる)
    sub alloc(uword id, ubyte size_h, uword size_lm) -> byte
    {
        ubyte bank_backup = cx16.getrambank()
        byte result = -1

        uword handle_addr = $a000 +  id * MEM_MAN_SIZE
        ; もし確保されていたら解放しておく
        free(id)

        ; 与えられた24bitサイズをCommander X16の8Kバンクサイズに合わせる
        uword cxsize = size_lm & $1fff
        ubyte cxbank = ((size_lm >> 13) | (size_h << 3)) as ubyte

        ; sizeがおさまりきる未使用領域があればそれを探して確保する
        if search_free(cxbank, cxsize)
        {
            ; 確保できた
            ; このタイミングbank_curとaddr_curは確保された領域の先頭を指している

            ; 該当バンクについてサイズ分割が可能な場合は分割を行い2つの領域にする
            ; mem_size & mem_bank_sizeが空き領域サイズなので、そこから、
            ; cxbankとcxsizeを引いた残りサイズが新しい空き領域となる
            ; その領域が3バイト以上ある場合は新しい空き領域を作成する

            ; 保存しておく
            ubyte target_bank = bank_cur
            uword target_addr = addr_cur

            uword remain_size = mem_size - cxsize
            ubyte remain_bank = mem_bank_size - cxbank
            if (remain_size & $8000) != 0
            {
                remain_bank = remain_bank - 1
                remain_size = remain_size & $1fff
            }
            ; 16バイト+4バイト(管理領域)以上の空き領域がある場合はメモリ分割する
            bool is_divide = remain_bank > 0 or remain_size >= 20
            ; 管理領域ぶん減らしておく
            if is_divide
            {
                remain_size = remain_size - 4
                if (remain_size & $8000) != 0
                {
                    remain_bank = remain_bank - 1
                    remain_size = remain_size & $1fff
                }
            }

            ; 分割元をcxbank, cxsizeに合わせる
            ubyte cxinfo = $80 | (mem_info & $f8)
            if is_divide
            {
                cxinfo = cxinfo & ~$40
            }
            put_byte(cxinfo)
            if is_divide
            {
                put_byte(lsb(cxsize))
                put_byte(msb(cxsize))
                put_byte(cxbank)
            } else {
                ; 分割しない場合はメモリ容量を維持する
                add_address(0, 3)
            }
            ; ここでデータ領域の先頭まで進んでいる

            ; 領域分割が可能な場合は領域分割して新しい空き領域を作成する
            if is_divide
            {
                ; 新しい空き領域を作成する
                add_address(cxbank, cxsize)
                put_byte(mem_info & $40)
                put_byte(lsb(remain_size))
                put_byte(msb(remain_size))
                put_byte(remain_bank)
            }

            ; 位置を戻す(いらんかも？)
            addr_cur = target_addr
            bank_cur = target_bank

            ; 管理領域のあるバンクに戻り、ハンドルのアドレスを設定する
            cx16.rambank(bank_top)
            @(handle_addr) = lsb(addr_cur)
            @(handle_addr + 1) = msb(addr_cur)
            @(handle_addr + 2) = bank_cur

            ; 確保完了
            result = 0
        }

        cx16.rambank(bank_backup)
        return result 
    }

    sub free(uword id)
    {
        ubyte bank_backup = cx16.getrambank()

        cx16.rambank(bank_top)
        uword handle_addr = $a000 +  id * MEM_MAN_SIZE 
        uword mem_addr = @(handle_addr)
        mem_addr = mem_addr + ((@(handle_addr + 1) as uword) << 8)
        ubyte mem_bank = @(handle_addr + 2)

        ; 確保済の場合は解放する
        if mem_addr != 0 or mem_bank != 0
        {
            ; 管理領域について未使用状態にする
            set_address(mem_bank, mem_addr)
            ubyte info = get_byte()
            sub_address(0, 1)
            put_byte(info & ~$80)

            ; ハンドル情報をクリア
            @(handle_addr) = 0
            @(handle_addr + 1) = 0
            @(handle_addr + 2) = 0
        }

        ; 連続した空き領域をマージする
        merge_free()

        cx16.rambank(bank_backup)
    }

    sub read_handle(uword id, ubyte ofs, uword mem_bank, uword mem_addr)
    {
        cx16.rambank(bank_top)

        uword handle_addr = $a000 +  id * MEM_MAN_SIZE  + ofs
        @(mem_addr) = @(handle_addr)
        @(mem_addr+1) = @(handle_addr + 1)
        @(mem_bank) = @(handle_addr + 2)

        bank_cur = 0
        addr_cur = handle_addr + 3
    }
    
    sub setup_data_addr(uword id) -> byte
    {
        byte result = -1

        ubyte mem_bank
        uword mem_addr
        read_handle(id, 0, &mem_bank, &mem_addr)

        if mem_addr != 0 or mem_bank != 0
        {
            set_address(mem_bank, mem_addr)
            add_address(0, 4)

            result = 0
        }
        return result
    }

    sub open(uword id)
    {
        ubyte bank_backup = cx16.getrambank()

        ubyte mem_bank
        uword mem_addr
        read_handle(id, 0, &mem_bank, &mem_addr)

        ; 管理領域を飛ばしてデータ領域まで持っていく
        mem_addr = mem_addr + 4
        while mem_addr >= $c000
        {
            mem_addr = mem_addr - $2000
            mem_bank = mem_bank + 1
        }

        ; ↑の後にaddr_curは現在アクセス中のアドレスの先頭を指している(複数ファイルモード)
        put_byte(lsb(mem_addr))
        put_byte(msb(mem_addr))
        put_byte(mem_bank)

        cx16.rambank(bank_backup)
    }

    ; open済メモリidからsizeバイトをaddrのアドレスに読み込む
    sub write(uword id, uword size, uword addr)
    {
        ubyte bank_backup = cx16.getrambank()

        ubyte mem_bank
        uword mem_addr
        read_handle(id, 3, &mem_bank, &mem_addr)
        ; 更新用にアドレスを保存しておく
        uword handle_cur_addr = addr_cur - 3

        ; mem_bank/mem_addrに現在アクセス位置が入っている
        set_address(mem_bank, mem_addr)
        ; TODO 最適化
        while size > 0
        {
            put_byte(@(addr))
            addr = addr + 1
            size = size - 1
        }
        ; 読み書き位置を更新
        cx16.rambank(bank_top)

        ; 読み込み位置を更新
        @(handle_cur_addr) = lsb(addr_cur)
        @(handle_cur_addr + 1) = msb(addr_cur)
        @(handle_cur_addr + 2) = bank_cur

        cx16.rambank(bank_backup)
    }

    ; open済メモリidにsizeバイトをaddrのアドレスから書き込む
    sub read(uword id, uword size, uword addr)
    {
        ubyte bank_backup = cx16.getrambank()

        ubyte mem_bank
        uword mem_addr
        read_handle(id, 3, &mem_bank, &mem_addr)
        ; 更新用にアドレスを保存しておく
        uword handle_cur_addr = addr_cur - 3

        ; mem_bank/mem_addrに現在アクセス位置が入っている
        set_address(mem_bank, mem_addr)
        ; TODO 最適化
        while size > 0
        {
            @(addr) = get_byte()
            addr = addr + 1
            size = size - 1
        }

        ; 読み書き位置を更新
        cx16.rambank(bank_top)

        ; 書き込み位置を更新
        @(handle_cur_addr) = lsb(addr_cur)
        @(handle_cur_addr + 1) = msb(addr_cur)
        @(handle_cur_addr + 2) = bank_cur

        cx16.rambank(bank_backup)
    }

    sub seek(uword id, byte bank, word size)
    {
        ubyte bank_backup = cx16.getrambank()

        ubyte mem_bank
        uword mem_addr
        read_handle(id, 3, &mem_bank, &mem_addr)
        uword handle_cur_addr = addr_cur - 3
        
        txt.print("seek:")
        txt.print_uwhex(mem_addr, true)
        txt.print(" : ")
        txt.print_ubhex(mem_bank, false)
        txt.nl()

        ; bankとsizeを足す
        mem_addr = mem_addr + size as uword
        while mem_addr >= $c000
        {
            mem_addr = mem_addr - $2000
            mem_bank = mem_bank + 1
        }
        while mem_addr < $a000
        {
            mem_addr = mem_addr + $2000
            mem_bank = mem_bank - 1
        }
        mem_bank = mem_bank + (bank as ubyte)

        txt.print("seek end:")
        txt.print_uwhex(mem_addr, true)
        txt.print(" : ")
        txt.print_ubhex(mem_bank, false)
        txt.nl()

        ; シーク位置設定
        cx16.rambank(bank_top)
        @(handle_cur_addr) = lsb(mem_addr)
        @(handle_cur_addr + 1) = msb(mem_addr)
        @(handle_cur_addr + 2) = mem_bank

        cx16.rambank(bank_backup)
    }

    ; 非バンクメモリの内容をバンクメモリに書き込む
    sub set_mem(uword id, uword addr, uword size)
    {
        if alloc(id, 0, size) == 0
        {
            if setup_data_addr(id) == 0
            {
                ; TODO 最適化
                while size > 0
                {
                    put_byte(@(addr))
                    addr = addr + 1
                    size = size - 1
                }
            }
        }
    }

    ; バンクメモリの内容を非バンクメモリに読み込む
    sub get_mem(uword id, uword addr, uword size)
    {
        bool is_not_exists = setup_data_addr(id) != 0
        if is_not_exists
        {
            ; 無い場合は初期サイズ(仮で32バイト中身不定、最初の2バイトは0)を確保
            void alloc(id, 0, 32)
            void setup_data_addr(id)
            put_byte(0)
            put_byte(0)
            sub_address(0, 2)
        }

        ; TODO 最適化
        while size > 0
        {
            @(addr) = get_byte()
            addr = addr + 1
            size = size - 1
        }
    }

    ; 連続する空き領域をマージして1つの領域にする
    sub merge_free()
    {
        set_address(bank_top, data_top)
        ubyte info
        uword mmem_size
        ubyte mmem_bank_size
        bool is_first = true
        bool is_connectable = false

        uword first_free_addr
        ubyte first_free_bank
        uword first_free_size
        ubyte first_free_bank_size
        do {
            info = get_byte()
            mmem_size = get_byte()
            mmem_size = mmem_size + ((get_byte() as uword) << 8)
            mmem_bank_size = get_byte()
            if (info & $80) != 0
            {
                ; 使用中の場合は次に進む
                add_address(mmem_bank_size, mmem_size)
                is_first = true
            } else {
                if is_first
                {
                    ; 未使用の場合、最初に発見した未使用の場合はその位置とサイズを拾っておく
                    sub_address(0, 4)
                    first_free_addr = addr_cur
                    first_free_bank = bank_cur
                    add_address(0, 4)
                    first_free_size = mmem_size
                    first_free_bank_size = mmem_bank_size

                    add_address(mmem_bank_size, mmem_size)
                    is_first = false
                } else {
                    ; ここに来た場合空き領域が連続しているので、最初の領域を拡張する(複数回連続していた場合、どんどん足される)
                    ; メモリ位置を記憶する
                    uword backup_free_addr = addr_cur
                    ubyte backup_free_bank = bank_cur

                    ; 最初の領域のサイズを更新
                    first_free_size = first_free_size + mmem_size + 4
                    first_free_bank_size = first_free_bank_size + mmem_bank_size
                    while first_free_size >= $c000
                    {
                        first_free_size = first_free_size - $2000
                        first_free_bank_size = first_free_bank_size + 1
                    }

                    set_address(first_free_bank, first_free_addr)
                    put_byte(info & $40)
                    ; ここから新規のサイズを書き戻す
                    put_byte(lsb(first_free_size))
                    put_byte(msb(first_free_size))
                    put_byte(first_free_bank_size)

                    ; マージ完了したので元の位置に戻す
                    set_address(backup_free_bank, backup_free_addr)
                    add_address(mmem_bank_size, mmem_size)
                }
            }
        } until info & $40
    }

    sub move_handle(uword from_id, uword count, bool is_insert)
    {
        ubyte bank_backup = cx16.getrambank()

        uword i
        uword line_max = from_id + count
        uword from_addr
        uword to_addr

        ; from_idをfrom_id+1にコピーしていく
        cx16.rambank(bank_top)
        if is_insert
        {
            for i in line_max downto from_id
            {
                from_addr = $a000 + i * MEM_MAN_SIZE
                to_addr = $a000 + (i + 1) * MEM_MAN_SIZE

                @(to_addr) = @(from_addr)
                @(to_addr + 1) = @(from_addr + 1)
                @(to_addr + 2) = @(from_addr + 2)
            }
            from_addr = $a000 + from_id * MEM_MAN_SIZE
        } else {
            for i in from_id + 1 to line_max
            {
                from_addr = $a000 + i * MEM_MAN_SIZE
                to_addr = $a000 + (i - 1) * MEM_MAN_SIZE

                @(to_addr) = @(from_addr)
                @(to_addr + 1) = @(from_addr + 1)
                @(to_addr + 2) = @(from_addr + 2)
            }
            from_addr = $a000 + line_max * MEM_MAN_SIZE
        }
        ; from_idについてはfree状態にする
        @(from_addr) = 0
        @(from_addr + 1) = 0
        @(from_addr + 2) = 0

        cx16.rambank(bank_backup)
    }

    sub debug_print()
    {
        ubyte bank_backup = cx16.getrambank()

        set_address(bank_top, data_top)

        ; データ状況を確認
        do {
            ubyte info = get_byte()
            uword size
            ubyte bank_sz = 0
            size = get_byte()
            size = size + ((get_byte() as uword) << 8)
            bank_sz = get_byte()

            txt.print("info:")
            txt.print_ubhex(info, false)
            txt.print(" size:")
            txt.print_uwhex(size, true)
            txt.print(" bank_size:")
            txt.print_ubhex(bank_sz, false)

            txt.nl()
            txt.print("------------")
            txt.nl()
            ; 次の領域に移動
            add_address(bank_sz, size)
        } until info & $40

        void cbm.CHRIN()

        cx16.rambank(bank_backup)
    }
}