" FIXME:
"
" Implement caching taking inspiration from:
"
"     https://github.com/google/vim-searchindex/blob/master/plugin/searchindex.vim
"
" FIXME:
" the cursor jumps briefly onto the command line when we hit `n`

" blink "{{{

" `s:blink` must be initialized before defining the functions
" `s:blink.tick()` and `s:blink.clear()`.
let s:blink = { 'ticks': 5, 'delay': 50 }

"                ┌─ when `timer_start()` will call this function, it will send
"                │  the timer ID
"                │
fu! s:blink.tick(_) abort
    let self.ticks -= 1

    let active = self.ticks > 0

    " FIXME:
    " Don't understand this line:
    if !self.clear() && &hlsearch && active
    " `!self.clear()` is true iff `w:blink_id` doesn't exist.

        " '\v%%%dl%%>%dc%%<%dc'
        "    │    │     │
        "    │    │     └─ '%<'.(col('.')+2).'c'      →    before    column    `col('.')+2`
        "    │    └─ '%<'.max([0, col('.')-2]).'c'    →    after     column    `max(0, col('.')-2)`
        "    └─ '%'.line('.').'l'                     →    on        line      `line('.')`

        let w:blink_id = matchadd('IncSearch',
                       \          printf(
                       \                 '\v%%%dl%%>%dc%%<%dc',
                       \                  line('.'),
                       \                  max([0, col('.')-3]),
                       \                  col('.')+3
                       \                )
                       \         )
    endif

    if active
        " call `s:blink.tick()` (current function) after `s:blink.delay` ms
        call timer_start(self.delay, self.tick)
        "                            │
        "                            └─ it's a funcref, so no need to surround
        "                               it with single quotes
    endif
endfu

" In `s:blink.tick()`, we test the output of this function to decide
" whether we should create a match.
fu! s:blink.clear() abort
    if exists('w:blink_id')
        call matchdelete(w:blink_id)
        unlet w:blink_id
        return 1
    endif
    " A function returns 0 by default, so no need to write `return 0`.
endfu

fu! search#blink() abort
    " we must reset the keys `ticks` and `delay` inside `s:blink`,
    " every time `search#blink()` is called
    let [ s:blink.ticks, s:blink.delay ] = [ 5, 50 ]

    call s:blink.clear()
    call s:blink.tick(0)
    return ''
endfu

"}}}
" cr "{{{

fu! s:cr(line) abort
    " g//#
    if a:line =~# '^g.*#$'
        " If we're on the Ex command line, it ends with a number sign, and we
        " hit Enter, return the Enter key, and add a colon at the end of it.
        "
        " Why?
        " Because `:#` is a command used to print lines with their addresses:
        "     :g/pattern/#
        "
        " And, when it's executed, we probably want to jump to one of them, by
        " typing its address on the command line:
        "     https://gist.github.com/romainl/047aca21e338df7ccf771f96858edb86

        return "\<cr>:"

    " ls
    elseif a:line =~# '\v\C^\s*%(ls|buffers|files)\s*$'

        return "\<cr>:b "

    " ilist
    elseif a:line =~# '\v\C^\s*%(d|i)l%[ist]\s+'

        return "\<cr>:".matchstr(a:line, '\S').'j '

    " clist
    elseif a:line =~# '\v\C^\s*%(c|l)l%[ist]\s*$'

        " allow Vim's pager to display the full contents of any command,
        " even if it takes more than one screen; don't stop after the first
        " screen to display the message:    -- More --
        set nomore

        " reset 'more' after the keys have been typed
        call timer_start(10, s:snr().'reset_more')

        return "\<cr>:".repeat(matchstr(a:line, '\S'), 2).' '

    " chistory
    elseif a:line =~# '\v\C^\s*%(c|l)hi%[story]\s*$'

        set nomore
        call timer_start(10, s:snr().'reset_more')
        return "\<cr>:sil ".matchstr(a:line, '\S').'older '

    " oldfiles
    elseif a:line =~# '\v\C^\s*old%[files]\s*$'

        set nomore
        call timer_start(10, s:snr().'reset_more')
        return "\<cr>:e #<"

    " changes
    elseif a:line =~# '\v\C^\s*changes\s*$'

        set nomore
        call timer_start(10, s:snr().'reset_more')
        " We don't return the keys directly, because S-left could be remapped
        " to something else, leading to spurious bugs.
        " We need to tell Vim to not remap it. We can't do that with `:return`.
        " But we can do it with `feedkeys()` and the `n` flag.
        call feedkeys("\<cr>:norm! g;\<s-left>", 'in')
        return ''

    " jumps
    elseif a:line =~# '\v\C^\s*ju%[mps]\s*$'

        set nomore
        call timer_start(10, s:snr().'reset_more')
        call feedkeys("\<cr>:norm! \<c-o>\<s-left>", 'in')
        "                                              │
        "                                              └─ don't remap C-o and S-left
        return ''

    " marks
    elseif a:line =~# '\v\C^\s*marks\s*$'

        set nomore
        call timer_start(10, s:snr().'reset_more')
        return "\<cr>:norm! `"

    else
        return "\<cr>"
    endif
endfu

"}}}
" echo_msg "{{{

fu! search#echo_msg() abort
    if s:seq ==? 'n'

        let winview     = winsaveview()
        let [line, col] = [winview.lnum, winview.col]

        call cursor(1, 1)
        let [idx, total]          = [1, 0]
        let [matchline, matchcol] = searchpos(@/, 'cW')
        while matchline && total <= 999
            let total += 1
            if matchline < line || (matchline == line && matchcol <= col)
                let idx += 1
            endif
            let [matchline, matchcol] = searchpos(@/, 'W')
        endwhile

        echo @/.'('.idx.'/'.total.')'
    endif

    return ''
endfu

"}}}
" escape "{{{

fu! search#escape(backward) abort
    return '\V'.substitute(escape(@", '\' . (a:backward ? '?' : '/')), "\n", '\\n', 'g')
endfu

"}}}
" immobile "{{{

fu! search#immobile(seq) abort
    let s:winline = winline()
    return a:seq."\<plug>(ms_prev)"
endfu

"}}}
" nohl_and_blink "{{{

" `nohl_and_blink()` does 4 things:
"
"     1. install a fire-once autocmd to disable 'hlsearch' as soon as we move the cursor
"     2. open possible folds
"     3. restore the position of the window
"     4. make the cursor blink

fu! search#nohl_and_blink() abort
    augroup my_search
        au!
        au CursorMoved,CursorMovedI * set nohlsearch | au! my_search | aug! my_search
    augroup END

    let seq = foldclosed('.') != -1 ? 'zMzv' : ''

    " What are `s:winline` and `s:windiff`? "{{{
    "
    " `s:winline` exists only if we hit `*`, `#` (visual/normal), `g*` or `g#`.
    "
    " NOTE:
    "
    " The goal of `s:windiff` is to restore the state of the window after we
    " search with `*` and similar normal commands (`#`, `g*`, `g#`).
    "
    " When we hit `*`, the `{rhs}` of the `*` mapping is evaluated as an
    " expression. During the evaluation, `search#immobile()` is called, which set
    " the variable `s:winline`. The result of the evaluation is:
    "
    "     <plug>(ms_nohl_and_blink)*<plug>(ms_prev)
    "
    " … which is equivalent to:
    "
    "     :call <sid>nohl_and_blink_on_leave()<CR>*<C-o>
    "
    " What's important to understand here, is that `nohl_and_blink()` is
    " called AFTER `search#immobile()`. Therefore, `s:winline` is not necessarily
    " the same as the current output of `winline()`, and we can use:
    "
    "     winline() - s:winline
    "
    " … to compute the number of times we have to hit `C-e` or `C-y` to
    " position the current line in the window, so that the state of the window
    " is restored as it was before we hit `*`.

"}}}

    if exists('s:winline')
        let windiff = winline() - s:winline
        unlet s:winline

        " If `windiff` is positive, it means the current line is further away
        " from the top line of the window, than it was originally.
        " We have to move the window down to restore the original distance
        " between current line and top line.
        " Thus, we use `C-e`. Otherwise, we use `C-y`.

        let seq .= windiff > 0
                 \   ? windiff."\<c-e>"
                 \   : windiff < 0
                 \     ? -windiff."\<c-y>"
                 \     : ''
    endif

    return seq."\<plug>(ms_blink)"
endfu

"}}}
" nohl_and_blink_on_leave "{{{

fu! search#nohl_and_blink_on_leave()
    augroup my_search
        au!
        au InsertLeave * call search#nohl_and_blink() | au! my_search | aug! my_search
    augroup END
    return ''
endfu

"}}}
" reset_more "{{{

fu! s:reset_more(...)
    set more
endfu

"}}}
" snr "{{{

fu! s:snr()
    return matchstr(expand('<sfile>'), '<SNR>\d\+_')
endfu

"}}}
" wrap "{{{

" `wrap()` enables 'hlsearch' then calls `nohl_and_blink()`
fu! search#wrap(seq) abort
    if mode() ==# 'c' && getcmdtype() ==# ':' && a:seq ==# "\<cr>"
        return s:cr(getcmdline())
    endif

    " we store the key inside `s:seq` so that `echo_msg()` knows whether it must
    " echo a msg or not
    let s:seq = a:seq

    " FIXME:
    " how to get `n` `N` to move consistently no matter the direction of the
    " search `/`, or `?` ?
    " If we change the value of `s:seq` (`n` to `N` or `N` to `n`), when we perform
    " a backward search we have an error:
    "
    "         too recursive mapping
    "
    " Why?

    if a:seq ==? 'n'
        " toggle the value of `n`, `N`
        let s:seq = (a:seq ==# 'n' ? 'Nn' : 'nN')[v:searchforward]
        " " convert it into a non-recursive mapping to avoid error "too recursive mapping"
        " " Pb: when we use non-recursive mapping, we don't see the message anymore
        " " Maybe because the non-recursive mapping is expanded after the
        " " message has been displayed ?
        "
        " let s:seq = (s:seq ==# 'n' ? "\<plug>(ms_n)" : "\<plug>(ms_N)")
        "
        " " Move mappings outside function:
        " nno <plug>(ms_n) n
        " nno <plug>(ms_N) N
    else
        let s:seq = a:seq
    endif

    sil! au! my_search | aug! my_search
    set hlsearch

    return s:seq."\<plug>(ms_nohl_and_blink)\<plug>(ms_echo_msg)"
endfu

"}}}
