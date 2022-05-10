;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(uiop:define-package :nyxt/xmpp-mode
  (:use :common-lisp :nyxt)
  (:import-from #:class-star #:define-class)
  (:import-from #:keymap #:define-key #:define-scheme)
  (:import-from #:serapeum #:->)
  (:documentation "Mode for XMPP chats."))
(in-package :nyxt/xmpp-mode)
(use-nyxt-package-nicknames)

(define-mode xmpp-mode ()
  "A mode for XMPP chats management."
  ((rememberable-p nil)
   (style (theme:themed-css (theme *browser*)
            (* :font-family "monospace,monospace")
            (body
             :background-color theme:background)
            (textarea
             :border-width "4px"
             :border-color theme:primary
             :border-style "solid"
             :border-radius "0"
             :color theme:background
             :width "100%"
             :position "absolute"
             :bottom "1em"
             :left "0")
            (.chat
             :display "flex"
             :flex-direction "column-reverse")
            (.incoming
             :background-color theme:text
             :color theme:background
             :align-self "flex-start")
            (.outbound
             :background-color theme:quaternary
             :color theme:text
             :text-align "right"
             :align-self "flex-end")))
   (connection
    nil
    :type (maybe xmpp:connection)
    ;; FIXME: Do we allow multiple accounts?
    ;; Should it be configured per buffer instead?
    ;; XMPP authentication is a pain, though...
    :allocation :class
    :documentation "The currently established XMPP connection.")
   (recipient
    :type string
    :documentation "The JID of the person the current chat happens with.")
   (messages
    '()
    :type list
    :documentation "The history of all the incoming and outbound messages associated with the current `connection'."))
  (:toggler-command-p nil))

(define-command xmpp-connect (&optional (mode (find-submode 'xmpp-mode)))
  "Connect to the chosen XMPP server."
  (let* ((hostname (prompt1
                     :prompt "XMPP server hostname"
                     :sources (list (make-instance 'prompter:raw-source))))
         (jid (if-confirm ("Does the server have matching hostname and JID part?")
                          hostname
                          (prompt1
                            :prompt "XMPP server JID pard"
                            :sources (list (make-instance 'prompter:raw-source)))))
         (connection (xmpp:connect-tls :hostname hostname :jid-domain-part jid)))
    (setf (connection mode) connection)
    (let* ((username (prompt1
                       :prompt (format nil "Your username at ~a" hostname)
                       :sources (list (make-instance 'prompter:raw-source))))
           (password (prompt1
                       :prompt "Password"
                       :invisible-input-p t
                       :sources (list (make-instance 'prompter:raw-source))))
           (auth-type (prompt1
                        :prompt "Authorization type"
                        :sources (list (make-instance
                                        'prompter:source
                                        :name "Auth types"
                                        :constructor (list :plain :sasl-plain :digest-md5 :sasl-digest-md5))))))
      (xmpp:auth (connection mode) username password "" :mechanism auth-type))))

(defmethod xmpp:handle ((connection xmpp:connection) (message xmpp:message))
  (let ((mode (find-submode 'xmpp-mode)))
    (push message (messages mode))
    (reload-buffers (list (buffer mode))))
  message)

(defmethod xmpp:handle ((connection xmpp:connection) object)
  (echo "Got ~a of type ~a." object (type-of object))
  object)

(define-internal-scheme "xmpp"
    (lambda (url buffer)
      (enable-modes '(xmpp-mode) buffer)
      (let* ((mode (find-submode 'xmpp-mode buffer)))
        (setf (recipient mode) (quri:uri-path (nyxt::ensure-url url)))
        (unless (connection mode)
          (xmpp-connect mode))
        (values
         (spinneret:with-html-string
           (:head
            (:style (style buffer))
            (:style (style mode)))
           (:body
            (:div
             :class "chat"
             (dolist (message (messages mode))
               (:div :class (if (string= (xmpp:from message) (xmpp:username (connection mode)))
                                "outbound"
                                "incoming")
                     (xmpp:body message))))
            (:textarea :placeholder (format nil "Put your message to ~a here" (recipient mode)))))
         "text/html;charset=utf8"))))
