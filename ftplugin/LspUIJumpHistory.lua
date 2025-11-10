-- 跳转历史语法高亮
-- 当 buffer 的 filetype 设置为 "LspUIJumpHistory" 时自动加载

vim.cmd([[
    syntax match HistoryTime /\[\d\d:\d\d:\d\d\]/
    syntax match HistoryType /│\s*\zs[a-zA-Z_]\+\ze\s*│/
    syntax match HistoryFile /│\s*\zs[^:]\+:\d\+\ze\s*│/
    syntax match HistorySeparator /[─│]/
    
    highlight default link HistoryTime Comment
    highlight default link HistoryType Keyword
    highlight default link HistoryFile Directory
    highlight default link HistorySeparator Comment
]])
