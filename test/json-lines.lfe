;;; Test-only port of AuctionSite.Persistence.JsonFile.
;;;
;;; The port's event store is a disk_log, so this JSONL reader/writer exists
;;; purely to exercise the command codec against the upstream sample file and
;;; to reproduce SerializationSpec's read/write round trip.
(defmodule json-lines
  (export
   (read-commands 1)
   (write-commands 2)))

(defun read-commands (path)
  (case (file:read_file path)
    (`#(ok ,contents) (decode-lines (binary:split contents #"\n" '(global))))
    (_ 'none)))

(defun decode-lines (lines)
  (try
    `#(ok ,(lists:append
            (lists:map (lambda (line) (decode-line line))
                       (lists:filter (lambda (l) (=/= l #"")) lines))))
    (catch ((tuple _ _ _) 'none))))

(defun decode-line (line)
  (lists:map
   (lambda (obj)
     (case (commands:command-from-json obj)
       (`#(ok ,cmd) cmd)
       (`#(error ,reason) (error reason))))
   (json:decode line)))

(defun write-commands (path cmds)
  (let ((encoded (erlang:iolist_to_binary
                  (json:encode (lists:map (lambda (c) (commands:command-to-json c))
                                          cmds)))))
    (case (filelib:is_regular path)
      ('true (file:write_file path
                              (erlang:iolist_to_binary (list #"\n" encoded))
                              '(append)))
      ('false (file:write_file path encoded)))))
