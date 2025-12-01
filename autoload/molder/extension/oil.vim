if exists('g:loaded_molder_edit')
  finish
endif
let g:loaded_molder_edit = 1

function! s:make_id(name) abort
  return sha256(a:name .. '-' .. localtime() .. '-' .. reltimestr(reltime()))[:8]
endfunction

function! s:normalize_name(name) abort
  return substitute(a:name, '[/\\]$', '', '')
endfunction

let s:idmap = {}
let s:idname = 'molder-oil'

function! s:prop_add_line_id(lnum, file) abort
  if len(prop_list(a:lnum, {'type':s:idname})) > 0
    call prop_clear(a:lnum)
  endif
  let l:id = s:make_id(a:file)
  let l:prop_id = prop_add(a:lnum, 0, {'type':s:idname, 'text':l:id, 'text_align':'right'})
  let s:idmap[l:prop_id] = {'id': l:id, 'name': a:file}
endfunction

function! s:get_line_textprop(lnum) abort
  let l:prop = get(prop_list(a:lnum), 0, {})
  if !empty(l:prop)
    if has_key(l:prop, 'id')
      return s:idmap[l:prop['id']]
    endif
    let l:text = get(l:prop, 'text', '')
    for [l:k, l:v] in items(s:idmap)
      if l:v['id'] == l:text
        return l:v
      endif
    endfor
  endif
  return {'id': '', 'name': ''}
endfunction

function! molder#extension#oil#init() abort
  call s:molder_edit_start()
endfunction

function! s:molder_edit_start() abort
  "let s:idmap = {}

  let l:dir = molder#curdir()
  let l:files = getline(1, '$')
  let l:sep = has('win32') || has('win64') ? '\' : '/'

  setlocal modifiable buftype=acwrite noreadonly

  if empty(prop_type_get(s:idname))
    call prop_type_add(s:idname, { 'highlight': 'NonText' })
  endif

  " Clear existing text properties
  for l:lnum in range(1, line('$'))
    call prop_clear(l:lnum)
  endfor

  for l:lnum in range(len(l:files))
    call s:prop_add_line_id(l:lnum+1, l:files[l:lnum])
  endfor

  augroup molder_edit
    autocmd! * <buffer>
    autocmd BufWriteCmd <buffer> call <SID>molder_edit_apply()
  augroup END

  setlocal nomodified
endfunction

function! GetProp() abort
  let l:lnum = line('.')
  let l:prop = s:get_line_textprop(l:lnum)
  return l:prop
endfunction

function! s:molder_edit_apply() abort
  let l:dir = molder#curdir()
  let l:operations = []
  let l:sep = has('win32') || has('win64') ? '\' : '/'

  let l:lines = getline(1, '$')
  call filter(l:lines, 'v:val !~ ''^\s*$''')

  " Validate filenames
  for l:lnum in range(len(l:lines))
    let l:line = l:lines[l:lnum]
    let l:basename = substitute(l:line, '[/\\]$', '', '')
    
    if l:basename ==# '..' || l:basename ==# '.' || l:basename ==# ''
      echohl ErrorMsg
      echo 'Error: Invalid filename "' .. l:line .. '" on line ' .. (l:lnum + 1)
      echohl None
      return
    endif
    
    if l:basename =~# '\v^\.\.?[/\\]'
      echohl ErrorMsg
      echo 'Error: Invalid filename "' .. l:line .. '" on line ' .. (l:lnum + 1) .. ' (cannot start with ./ or ../)'
      echohl None
      return
    endif
    
    " Windows-specific validation
    if has('win32') || has('win64')
      if l:basename =~# '[<>:"|?*]'
        echohl ErrorMsg
        echo 'Error: Invalid filename "' .. l:line .. '" on line ' .. (l:lnum + 1) .. ' (contains invalid characters)'
        echohl None
        return
      endif
      
      let l:name_only = substitute(l:basename, '\.[^.]*$', '', '')
      if l:name_only =~? '^\(CON\|PRN\|AUX\|NUL\|COM[1-9]\|LPT[1-9]\)$'
        echohl ErrorMsg
        echo 'Error: Invalid filename "' .. l:line .. '" on line ' .. (l:lnum + 1) .. ' (reserved device name)'
        echohl None
        return
      endif
    endif
  endfor

  let l:will_be_deleted = []
  let l:processed_ids = []

  for l:lnum in range(len(l:lines))
    let l:line = l:lines[l:lnum]

    let l:prop = s:get_line_textprop(l:lnum+1)
    let l:oldname = l:prop['name']

    " new file/directory
    if l:prop['id'] ==# ''
      if l:line =~# '[/\\]$'
        call add(l:operations, 'CREATE ' .. l:line)
      else
        call add(l:operations, 'CREATE ' .. l:line)
      endif
      continue
    endif

    " move out
    if l:line =~# '[/\\].'
      if filereadable(l:dir .. l:sep .. l:oldname) || isdirectory(l:dir .. l:sep .. l:oldname)
        call add(l:operations, 'MOVE ' .. l:oldname .. ' TO ' .. l:line)
        call add(l:processed_ids, l:prop['id'])
      endif
      continue
    endif

    " rename
    if s:normalize_name(l:oldname) !=# s:normalize_name(l:line)
      if filereadable(l:dir .. l:sep .. l:oldname) || isdirectory(l:dir .. l:sep .. l:oldname)
        call add(l:operations, 'RENAME ' .. l:oldname .. ' TO ' .. l:line)
        call add(l:processed_ids, l:prop['id'])
      endif
    endif
  endfor

  for l:prop in values(s:idmap)
    let l:oldname = l:prop['name']
    if index(l:lines, l:oldname) ==# -1 && index(l:processed_ids, l:prop['id']) ==# -1
      call add(l:will_be_deleted, l:prop)
    endif
  endfor

  for l:prop in l:will_be_deleted
    let l:oldname = l:prop['name']
    if filereadable(l:dir .. l:sep .. l:oldname)
      call add(l:operations, 'DELETE ' .. l:oldname)
    elseif isdirectory(l:dir .. l:sep .. l:oldname)
      call add(l:operations, 'DELETE ' .. l:oldname)
    endif
  endfor

  if empty(l:operations)
    setlocal nomodified
    echohl WarningMsg
    echo 'No operations to apply.'
    echohl None
    return
  endif

  if get(g:, 'molder_oil_confirm_dialog', 1) == 1
    let l:confirm_text = ['Execute the following operations? [y]/[n]', ''] + l:operations
    let l:result = popup_dialog(l:confirm_text, #{
          \ title: 'Confirm File Operations',
          \ filter: 'popup_filter_yesno',
          \ callback: function('s:execute_operations', [l:lines, l:will_be_deleted])
          \ })
  else
    for l:operation in l:operations
      echo l:operation
    endfor
    if confirm('Execute the following operations?', "&Yes\n&No", 1) == 1
      call s:execute_operations(l:lines, l:will_be_deleted, '', 1)
    else
      call s:execute_operations(l:lines, l:will_be_deleted, '', 0)
    endif
  endif
endfunction

function! s:execute_operations(lines, will_be_deleted, id, result) abort
  if a:result != 1
    echohl WarningMsg
    echo 'Operations cancelled.'
    echohl None
    return
  endif

  let l:dir = molder#curdir()
  let l:qf = []
  let l:sep = has('win32') || has('win64') ? '\' : '/'

  for l:lnum in range(len(a:lines))
    let l:line = a:lines[l:lnum]

    let l:prop = s:get_line_textprop(l:lnum+1)
    let l:oldname = l:prop['name']

    " new file/directory
    if l:prop['id'] ==# ''
      if l:line =~# '[/\\]$'
        call mkdir(l:dir .. l:sep .. l:line, 'p')
      else
        call writefile([], l:dir .. l:sep .. l:line)
      endif
      call add(l:qf, {'text':'[+] created ' .. l:line})
      call s:prop_add_line_id(l:lnum+1, l:line)
      continue
    endif

    " move out
    if l:line =~# '[/\\].'
      if filereadable(l:dir .. l:sep .. l:oldname) || isdirectory(l:dir .. l:sep .. l:oldname)
        call rename(l:dir .. l:sep .. l:oldname, l:dir .. l:sep .. l:line)
        call add(l:qf, {'text':'[>] moved out ' .. l:oldname})
      endif
      continue
    endif

    " rename
    if s:normalize_name(l:oldname) !=# s:normalize_name(l:line)
      if filereadable(l:dir .. l:sep .. l:oldname) || isdirectory(l:dir .. l:sep .. l:oldname)
        call rename(l:dir .. l:sep .. l:oldname, l:dir .. l:sep .. l:line)
      endif
      call add(l:qf, {'text':'[~] renamed ' .. l:oldname .. ' -> ' .. l:line})
    endif
  endfor

  for l:prop in a:will_be_deleted
    let l:oldname = l:prop['name']
    if filereadable(l:dir .. l:sep .. l:oldname)
      call delete(l:dir .. l:sep .. l:oldname)
      call add(l:qf, {'text':'[-] deleted ' .. l:oldname})
    elseif isdirectory(l:dir .. l:sep .. l:oldname)
      call delete(l:dir .. l:sep .. l:oldname, 'rf')
      call add(l:qf, {'text':'[-] deleted dir ' .. l:oldname})
    endif
  endfor

  noautocmd noswapfile keepalt silent %g/[/\\]./d _
  setlocal nomodified

  if !empty(l:qf)
    call setqflist(l:qf)
    call setqflist([], 'r', {'title':'Molder Operations'})
    silent copen 8 | wincmd p
  else
    silent cclose
  endif

  redraw
  echohl ModeMsg
  echo 'File operations applied.'
  echohl None
endfunction

command! -nargs=0 Fileman call <SID>molder_edit_start()
