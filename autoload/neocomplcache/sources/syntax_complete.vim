"=============================================================================
" FILE: syntax_complete.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu@gmail.com>
" Last Modified: 26 Sep 2013.
" License: MIT license  {{{
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following conditions:
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
"=============================================================================

let s:save_cpo = &cpo
set cpo&vim

" Important variables.
if !exists('s:syntax_list')
  let s:syntax_list = {}
endif

let s:source = {
      \ 'name' : 'syntax_complete',
      \ 'kind' : 'keyword',
      \ 'mark' : '[S]',
      \ 'rank' : 4,
      \}

function! s:source.initialize() "{{{
  " Set caching event.
  autocmd neocomplcache Syntax * call s:caching()

  " Create cache directory.
  if !isdirectory(neocomplcache#get_temporary_directory() . '/syntax_cache')
     \ && !neocomplcache#util#is_sudo()
    call mkdir(neocomplcache#get_temporary_directory() . '/syntax_cache')
  endif

  " Initialize check.
  call s:caching()
endfunction"}}}

function! s:source.finalize() "{{{
  delcommand NeoComplCacheCachingSyntax
endfunction"}}}

function! s:source.get_keyword_list(complete_str) "{{{
  let list = []

  let filetype = neocomplcache#get_context_filetype()
  if !has_key(s:syntax_list, filetype)
    call s:caching()
  endif

  for syntax in neocomplcache#get_sources_list(
        \ s:syntax_list, filetype)
    let list += neocomplcache#dictionary_filter(syntax, a:complete_str)
  endfor

  " Static keyword lists, for filetypes whose syntax defines the compiler
  " directives and system tasks with regexes that cannot be enumerated.
  let list += neocomplcache#keyword_filter(
        \ copy(get(s:static_keywords, filetype, [])), a:complete_str)

  return list
endfunction"}}}

function! neocomplcache#sources#syntax_complete#define() "{{{
  return s:source
endfunction"}}}

function! s:threshold() "{{{
  return get(g:, 'neocomplcache_min_syntax_length', 4)
endfunction"}}}

function! s:cache_matches(lines) "{{{
  " The extracted keyword set depends on g:neocomplcache_min_syntax_length,
  " so the value it was built with is stored on the first line of the cache
  " file.  s:caching() only compares mtimes against syntax/<filetype>.vim,
  " so without the stored value a change of the option would keep loading a
  " cache built with the old one and short keywords (reg, bit, xor, ...)
  " would never come back.  The file name itself stays the plain filetype.
  " A cache from an older version is a single line and is rejected here, so
  " it gets rebuilt once.
  return len(a:lines) >= 2 && str2nr(a:lines[0]) == s:threshold()
endfunction"}}}

function! s:load_cache(lines) "{{{
  let keyword_lists = {}
  let completion_length = 2
  for keyword in eval(join(a:lines[1:], "\n"))
    let key = tolower(keyword[: completion_length-1])
    if !has_key(keyword_lists, key)
      let keyword_lists[key] = []
    endif
    call add(keyword_lists[key], keyword)
  endfor

  return keyword_lists
endfunction"}}}

function! s:caching() "{{{
  if &filetype == '' || &filetype ==# 'vim'
    return
  endif

  for filetype in neocomplcache#get_source_filetypes(&filetype)
    if !has_key(s:syntax_list, filetype)
      " Check old cache.
      " Use the loop variable filetype, not &filetype: for filetypes with a
      " same_filetype alias (c -> cpp), &filetype would make the alias read
      " the *real* filetype's cache and duplicate every keyword.
      let cache_name = neocomplcache#cache#encode_name('syntax_cache', filetype)
      let syntax_files = split(
            \ globpath(&runtimepath, 'syntax/'.filetype.'.vim'), '\n')
      let cache_lines = neocomplcache#cache#readfile('syntax_cache', filetype)
      if getftime(cache_name) < 0 || (!empty(syntax_files)
            \ && getftime(cache_name) <= getftime(syntax_files[0]))
            \ || !s:cache_matches(cache_lines)
        if filetype ==# &filetype
          " Caching from syn list.
          let s:syntax_list[filetype] = s:caching_from_syn(filetype)
        endif
      else
        let s:syntax_list[filetype] = s:load_cache(cache_lines)
      endif
    endif
  endfor
endfunction"}}}

function! neocomplcache#sources#syntax_complete#recaching(filetype) "{{{
  if a:filetype == ''
    let filetype = &filetype
  else
    let filetype = a:filetype
  endif

  " Caching.
  let s:syntax_list[filetype] = s:caching_from_syn(filetype)
endfunction"}}}

function! s:caching_from_syn(filetype) "{{{
  call neocomplcache#print_caching(
        \ 'Caching syntax "' . a:filetype . '"... please wait.')

  " Get current syntax list.
  redir => syntax_list
  silent! syntax list
  redir END

  if syntax_list =~ '^E\d\+' || syntax_list =~ '^No Syntax items'
    return []
  endif

  let group_name = ''
  let keyword_pattern = neocomplcache#get_keyword_pattern(a:filetype)

  let dup_check = {}

  " Some filetypes get their syntax groups from another filetype:
  " syntax/systemverilog.vim loads syntax/verilog.vim, so the Verilog
  " keywords live in the "verilog*" groups.  Accept the syntax groups of
  " the filetypes registered in
  " g:neocomplcache_syntax_group_filetype_lists as well.
  let filetypes = [a:filetype]
  if exists('g:neocomplcache_syntax_group_filetype_lists')
    let filetypes += split(get(
          \ g:neocomplcache_syntax_group_filetype_lists, a:filetype, ''), ',')
  endif

  let filetype_patterns = map(copy(filetypes), 'tolower(v:val)')

  let keyword_lists = {}
  for line in split(syntax_list, '\n')
    if line =~ '^\h\w\+'
      " Change syntax group name.
      let group_name = matchstr(line, '^\S\+')
      let line = substitute(line, '^\S\+\s*xxx', '', '')
    endif

    let is_target = 0
    for filetype_pattern in filetype_patterns
      " Note: stridx(), not strridx().  strridx() returns the *last*
      " occurrence, so a group name containing the filetype string more than
      " once failed this == 0 prefix test and the whole group was dropped
      " along with its keywords.  For C that silently discarded
      " cStructure (struct/union/enum), cStorageClass (static/const/extern/
      " auto/register/volatile), cConditional (if/else/switch), cPreProc,
      " cInclude and 36 more groups.
      if stridx(tolower(group_name), filetype_pattern) == 0
        let is_target = 1
        break
      endif
    endfor

    if line =~ 'Syntax items' || line =~ '^\s*links to' ||
          \ line =~ '^\s*nextgroup=' || line =~ 'cluster=' || !is_target
          \ || group_name =~? 'Todo$'
      " Next line.  A *Todo group only holds TODO/FIXME/XXX markers, never a
      " word you would want completed.
      continue
    endif

    let line = substitute(line, 'contained\|skipwhite\|skipnl\|oneline', '', 'g')
    let line = substitute(line, '^\s*nextgroup=.*\ze\s', '', '')

    if line =~ '^\s*match' || line =~ '^\s*start='
      if get(g:neocomplcache_syntax_skip_match_filetypes, a:filetype, 0)
        " Whole-rule regex rather than a literal keyword list: the "candidates"
        " extracted from it would be fragments (character classes, escape
        " classes, \z constructs), so skip the rule entirely.
        continue
      endif

      if line =~ '^\s*match'
        let line = s:substitute_candidate(matchstr(line, '/\zs[^/]\+\ze/'))
      else
        let line =
              \s:substitute_candidate(matchstr(line, 'start=/\zs[^/]\+\ze/')) . ' ' .
              \s:substitute_candidate(matchstr(line, 'end=/\zs[^/]\+\ze/'))
      endif
    endif

    " Add keywords.
    let match_num = 0
    let completion_length = 2
    let match_str = matchstr(line, keyword_pattern, match_num)
    while match_str != ''
      " Ignore too short keyword.
      if len(match_str) >= g:neocomplcache_min_syntax_length
            \ && !has_key(dup_check, match_str)
            \&& match_str =~ '^[[:print:]]\+$'
        let key = tolower(match_str[: completion_length-1])
        if !has_key(keyword_lists, key)
          let keyword_lists[key] = []
        endif
        call add(keyword_lists[key], match_str)

        let dup_check[match_str] = 1
      endif

      " Jump to the end of the match.  matchstr() starts searching at
      " match_num, so the match may begin later than match_num; advancing
      " by the match length would resume scanning inside the same word.
      let match_num = matchend(line, keyword_pattern, match_num)

      let match_str = matchstr(line, keyword_pattern, match_num)
    endwhile
  endfor

  " Save syntax cache.  Line 1 is the g:neocomplcache_min_syntax_length the
  " cache was built with, line 2 is the keyword list (see s:cache_matches()).
  let unpack_lists = neocomplcache#unpack_dictionary(keyword_lists)
  if !empty(unpack_lists)
    call neocomplcache#cache#writefile('syntax_cache', &filetype,
          \ [string(s:threshold()), string(unpack_lists)])
  endif

  call neocomplcache#print_caching('')

  return keyword_lists
endfunction"}}}

function! s:substitute_candidate(candidate) "{{{
  let candidate = a:candidate

  " Collection.
  let candidate = substitute(candidate,
        \'\\\@<!\[[^\]]*\]', ' ', 'g')

  " Delete.
  let candidate = substitute(candidate,
        \'\\\@<!\%(\\[=?+]\|\\%[\|\\s\*\)', '', 'g')
  " Space.
  let candidate = substitute(candidate,
        \'\\\@<!\%(\\[<>{}]\|[$^]\|\\z\?\a\)', ' ', 'g')

  if candidate =~ '\\%\?('
    let candidate = join(s:split_pattern(candidate))
  endif

  " \
  let candidate = substitute(candidate, '\\\\', '\\', 'g')
  " *
  let candidate = substitute(candidate, '\\\*', '*', 'g')
  return candidate
endfunction"}}}

function! s:split_pattern(keyword_pattern) "{{{
  let original_pattern = a:keyword_pattern
  let result_patterns = []
  let analyzing_patterns = [ '' ]

  let i = 0
  let max = len(original_pattern)
  while i < max
    if match(original_pattern, '^\\%\?(', i) >= 0
      " Grouping.
      let end = s:match_pair(original_pattern, '\\%\?(', '\\)', i)
      if end < 0
        "call neocomplcache#print_error('Unmatched (.')
        return [ a:keyword_pattern ]
      endif

      let save_pattern = analyzing_patterns
      let analyzing_patterns = []
      for keyword in split(original_pattern[matchend(original_pattern, '^\\%\?(', i) : end], '\\|')
        for prefix in save_pattern
          call add(analyzing_patterns, prefix . keyword)
        endfor
      endfor

      let i = end + 1
    elseif match(original_pattern, '^\\|', i) >= 0
      " Select.
      let result_patterns += analyzing_patterns
      let analyzing_patterns = [ '' ]
      let original_pattern = original_pattern[i+2 :]
      let max = len(original_pattern)

      let i = 0
    elseif original_pattern[i] == '\' && i+1 < max
      let save_pattern = analyzing_patterns
      let analyzing_patterns = []
      for prefix in save_pattern
        call add(analyzing_patterns, prefix . original_pattern[i] . original_pattern[i+1])
      endfor

      " Escape.
      let i += 2
    else
      let save_pattern = analyzing_patterns
      let analyzing_patterns = []
      for prefix in save_pattern
        call add(analyzing_patterns, prefix . original_pattern[i])
      endfor

      let i += 1
    endif
  endwhile

  let result_patterns += analyzing_patterns
  return result_patterns
endfunction"}}}

function! s:match_pair(string, start_pattern, end_pattern, start_cnt) "{{{
  let end = -1
  let start_pattern = '\%(' . a:start_pattern . '\)'
  let end_pattern = '\%(' . a:end_pattern . '\)'

  let i = a:start_cnt
  let max = len(a:string)
  let nest_level = 0
  while i < max
    let start = match(a:string, start_pattern, i)
    let end = match(a:string, end_pattern, i)

    if start >= 0 && (end < 0 || start < end)
      let i = matchend(a:string, start_pattern, i)
      let nest_level += 1
    elseif end >= 0 && (start < 0 || end < start)
      let nest_level -= 1

      if nest_level == 0
        return end
      endif

      let i = matchend(a:string, end_pattern, i)
    else
      break
    endif
  endwhile

  if nest_level != 0
    return -1
  else
    return end
  endif
endfunction"}}}

" Global options definition. "{{{
if !exists('g:neocomplcache_min_syntax_length')
  let g:neocomplcache_min_syntax_length = 4
endif
if !exists('g:neocomplcache_syntax_skip_match_filetypes')
  " Filetypes whose syntax/<filetype>.vim defines every real keyword with
  " "syn keyword" and uses "syn match"/"syn start" only for genuine regexes
  " (number formats, escape sequences, macro names).  Harvesting those rules
  " yields fragments such as "end_" (from /`end_\w\+/) or "bB" (from a
  " base-format character class), so they are skipped for these filetypes.
  let g:neocomplcache_syntax_skip_match_filetypes =
        \ {'systemverilog': 1, 'verilog': 1}
endif
if !exists('g:neocomplcache_syntax_group_filetype_lists')
  " Filetypes whose syntax groups are named after another filetype.
  " Caching only picks up the syntax groups which begin with the filetype
  " name, so these filetypes would otherwise miss those keywords.
  let g:neocomplcache_syntax_group_filetype_lists =
        \ {'systemverilog': 'verilog'}
endif
"}}}

" Static keyword lists. "{{{
" Some filetypes define their compiler directives and system tasks with
" "syn match" on regular expressions rather than "syn keyword", so the
" harvesting above yields either nothing (regex match rules are skipped for
" SystemVerilog/Verilog) or fragments.  Vim's "syn keyword" cannot carry
" these tokens either, because neither a backtick nor a dollar is a keyword
" character, so the generated \<word\> pattern never matches.  They are
" supplied here directly.  The SV/Verilog keyword pattern in init.vim has
" the matching `\h\w* and \$\h\w* branches that make these candidates
" recognisable while typing.
let s:directives = [
      \ '`__FILE__', '`__LINE__',
      \ '`begin_keywords', '`celldefine', '`default_nettype', '`define',
      \ '`else', '`elsif', '`end_keywords', '`endcelldefine', '`endif',
      \ '`ifdef', '`ifndef', '`include', '`line', '`nounconnected_drive',
      \ '`pragma', '`resetall', '`timescale', '`unconnected_drive', '`undef',
      \ ]
let s:system_tasks = [
      \ '$acos', '$acosh', '$asin', '$asinh', '$assertcontrol',
      \ '$assertfailoff', '$assertfailon', '$assertkill',
      \ '$assertnonvacuouson', '$assertoff', '$asserton',
      \ '$assertpassoff', '$assertpasson', '$assertvacuousoff',
      \ '$atan', '$atan2', '$atanh',
      \ '$bits', '$bitstoreal', '$bitstoshortreal',
      \ '$cast', '$ceil', '$changed', '$clog2', '$cos', '$cosh',
      \ '$countbits', '$countdrivers', '$countones',
      \ '$coverage_control', '$coverage_get', '$coverage_get_max',
      \ '$coverage_merge', '$coverage_save',
      \ '$dimensions', '$display', '$displayb', '$displayh', '$displayo',
      \ '$dist_chi_square', '$dist_erlang',
      \ '$dist_exponential', '$dist_normal', '$dist_poisson', '$dist_t',
      \ '$dist_uniform', '$dumpall', '$dumpfile', '$dumpflush', '$dumplimit',
      \ '$dumpoff', '$dumpon', '$dumpvars',
      \ '$error', '$exit', '$exp',
      \ '$fatal', '$fclose', '$fdisplay', '$fdisplayb', '$fdisplayh',
      \ '$fdisplayo', '$feof', '$ferror', '$fflush', '$fgetc', '$fgets',
      \ '$finish', '$floor', '$fmonitor', '$fmonitorb', '$fmonitorh',
      \ '$fmonitoro', '$fopen', '$fread', '$fscanf', '$fseek', '$fstrobe',
      \ '$fstrobeb', '$fstrobeh', '$fstrobeo', '$ftell', '$fullskew',
      \ '$fwrite', '$fwriteb', '$fwriteh', '$fwriteo',
      \ '$get_coverage', '$get_randstate', '$getpattern',
      \ '$high', '$hold', '$hypot',
      \ '$increment', '$info', '$input', '$isunbounded', '$isunknown',
      \ '$itor',
      \ '$left', '$ln', '$load_coverage_db', '$log10', '$low',
      \ '$monitor', '$monitorb', '$monitorh', '$monitoro', '$monitoroff',
      \ '$monitoron', '$nochange',
      \ '$onehot', '$onehot0', '$output', '$past', '$period', '$pow',
      \ '$printtimescale',
      \ '$random', '$readmemb', '$readmemh', '$realtime', '$realtobits',
      \ '$recovery', '$recrem', '$removal', '$rewind', '$right', '$root',
      \ '$rose', '$rtoi',
      \ '$sampled', '$set_coverage_db_name',
      \ '$set_randstate', '$setuphold', '$sformat', '$sformatf',
      \ '$shortrealtobits', '$signed', '$sin',
      \ '$sinh', '$size', '$skew', '$sqrt', '$sscanf', '$stable', '$stime',
      \ '$stop', '$strobe', '$strobeb', '$strobeh', '$strobeo', '$swrite',
      \ '$swriteb', '$swriteh', '$swriteo', '$system',
      \ '$tan', '$tanh', '$test$plusargs', '$time', '$timeformat',
      \ '$typename', '$unit', '$unpacked_dimensions', '$unsigned',
      \ '$urandom', '$urandom_range', '$value$plusargs',
      \ '$warning', '$width', '$write', '$writeb', '$writeh', '$writeo',
      \ '$writememb', '$writememh',
      \ ]
let s:static_keywords = {
      \ 'systemverilog' : s:directives + s:system_tasks,
      \ 'verilog'       : s:directives + s:system_tasks,
      \ }
"}}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: foldmethod=marker
