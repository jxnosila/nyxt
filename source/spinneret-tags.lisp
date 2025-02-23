;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(in-package :spinneret)

(deftag :mayberaw (body attrs &rest keys &key &allow-other-keys)
  "Spinneret's :raw, but with HTML escaping if BODY _does not_ look like HTML."
  ;; Because (declare (ignorable ...)) doesn't work.
  (let ((attrs attrs)
        (keys keys))
    (declare (ignorable attrs keys))
    `(:raw (if (nyxt:html-string-p (progn ,@body))
               (progn ,@body)
               (escape-string (progn ,@body))))))

(deftag :nstyle (body attrs &rest keys &key &allow-other-keys)
  "Regular <style>, but with contents staying unescaped."
  (let ((keys keys))
    (declare (ignorable keys))
    `(:style ,@attrs (:raw ,@body))))

(deftag :nscript (body attrs &rest keys &key &allow-other-keys)
  "Regular <script>, but with contents staying unescaped."
  (let ((keys keys))
    (declare (ignorable keys))
    `(:script ,@attrs (:raw ,@body))))

(serapeum:eval-always
  (defun remove-smart-quoting (form)
    "If the form is quoted or quasi-quoted, return the unquoted/evaluated variant.
Otherwise, return the form as is."
    (cond
      ((and (listp form)
            (eq 'quote (first form)))
       (second form))
      #+(or sbcl ecl)
      ((and (listp form)
            (eq #+sbcl 'sb-int:quasiquote
                #+ecl 'si:quasiquote
                ;; FIXME: CCL expands quasiquote to
                ;; `list*' call.
                ;; TODO: Other implementations?
                (first form)))
       (eval form))
      (t form))))

(deftag :nselect (body attrs &rest keys &key (id (alexandria:required-argument 'id)) &allow-other-keys)
  "Generate <select> tag from the BODY resembling cond clauses.

BODY forms can be of two kinds:

- (VALUE . FORMS) -- creates <option value=\"value\">value</option> and runs
  FORMS when it's selected.

- ((VALUE DISPLAY TITLE) . FORMS) -- creates an
  <option value=\"value\" title=\"title\">display</option>
  and runs FORMS when it's selected. DISPLAY and TITLE are optional literal
  strings.

In both cases, VALUE should be a literal (and printable) atom. For instance,
symbol, number, string, or keyword.

Example:
\(:nselect :id \"number-guessing\"
  (1 (nyxt:echo \"Too low!\"))
  (2 (nyxt:echo \"Correct!\"))
  (3 (nyxt:echo \"Too high!\")))"
  (with-gensyms (var)
    (once-only (id)
      (let ((keys keys))
        (declare (ignorable keys))
        `(:select.button
          ,@attrs
          :id ,id
          :onchange
          (when (nyxt:current-buffer)
            (ps:ps (nyxt/ps:lisp-eval
                    (:title "nselect-choice")
                    (let ((,var (nyxt:ps-eval (ps:chain (nyxt/ps:qs document (+ "#" (ps:lisp ,id))) value))))
                      (str:string-case ,var
                                       ,@(loop for (clause . forms) in (mapcar #'remove-smart-quoting body)
                                               for value = (first (uiop:ensure-list clause))
                                               collect (cons (nyxt:prini-to-string value)
                                                             forms)))))))
          ,@(loop for (clause) in (mapcar #'remove-smart-quoting body)
                  for value = (first (uiop:ensure-list clause))
                  for display = (second (uiop:ensure-list clause))
                  for title = (third (uiop:ensure-list clause))
                  collect `(:option
                            :value ,(nyxt:prini-to-string value)
                            ,@(when title
                                (list :title title))
                            ,(string-capitalize (or display (nyxt:prini-to-string value))))))))))

(defun %nxref-doc (type symbol &optional (class-name (when (eq type :slot)
                                                       (alexandria:required-argument 'class-name))))
  "NOTE: TYPE for classes is :CLASS, not :CLASS-NAME (as in `:nxref')."
  (format nil "[~a]~@[ ~a~]"
          (if class-name
              (format nil "SLOT of ~a" class-name)
              type)
          (when-let ((doc (case type
                            (:package (documentation (find-package symbol) t))
                            (:variable (documentation symbol 'variable))
                            ((:slot   ; KLUDGE: Any simple way to get slot docs?
                              :macro :function :command)
                             (documentation symbol 'function))
                            ((:mode :class)
                             (documentation symbol 'type)))))
            ;; Copied from describe.lisp to avoid `nyxt::first-line' use.
            (find-if (complement #'uiop:emptyp) (serapeum:lines doc)))))

(defun %nxref-link (type symbol &optional (class-name (when (eq type :slot)
                                                        (alexandria:required-argument 'class-name))))
  "Generate a nyxt: link to the describe-* page based on SYMBOL's TYPE.
CLASS-NAME is specific to :slot type."
  (case type
    (:package (nyxt:nyxt-url (read-from-string "nyxt:describe-package") :package symbol))
    (:variable (nyxt:nyxt-url (read-from-string "nyxt:describe-variable")
                              :variable symbol))
    ((:command :function :macro)
     (nyxt:nyxt-url (read-from-string "nyxt:describe-function")
                    :fn symbol))
    (:slot (nyxt:nyxt-url (read-from-string "nyxt:describe-slot")
                          :name symbol :class class-name))
    ((:mode :class)
     (nyxt:nyxt-url (read-from-string "nyxt:describe-class")
                    :class symbol))
    (t (nyxt:nyxt-url (read-from-string "nyxt:describe-any")
                      :input symbol))))

(deftag :nxref (body attrs &rest keys &key slot mode class-name function macro command (command-key-p t) variable package &allow-other-keys)
  "Create a link to a respective describe-* page for BODY symbol.

Relies on the type keywords (SLOT, MODE, CLASS-NAME, FUNCTION, MACRO, COMMAND,
VARIABLE, PACKAGE) to guess the right page, always provide those.

CLASS-NAME, if present, should be the symbol designating a class. It's not
called CLASS because Spinneret has special behavior for CLASS pre-defined and
non-overridable."
  (let* ((keys keys)
         (first (first body))
         (symbol (or package variable function macro command slot class-name mode
                     (when (symbolp first) first)))
         (printable (or (when (and (symbolp first) (eq first symbol))
                          (second body))
                        first package variable function macro command slot class-name mode))
         (type (cond
                 (package :package)
                 (variable :variable)
                 (macro :macro)
                 (command :command)
                 (function :function)
                 ((and slot class-name) :slot)
                 (mode :mode)
                 (class-name :class))))
    (declare (ignorable keys))
    `(:a.link
      :target "_blank"
      ,@attrs
      :href (%nxref-link ,type ,symbol
                         ,@(when (and slot class-name)
                             (list class-name)))
      :title (%nxref-doc ,type ,symbol
                         ,@(when (and slot class-name)
                             (list class-name)))
      ,@(when (and (getf attrs :class)
                   (or (getf attrs :slot)
                       (every #'null (list slot class-name mode function macro command variable package))))
          (error ":class attribute used ambiguously in :nxref tag. Use :class-name instead.")
          nil)
      (:code
       (let ((*print-escape* nil))
         (nyxt:prini-to-string ,printable))
       ,@(when (and command command-key-p)
           `(" ("
             (funcall (read-from-string "nyxt::binding-keys")
                      ,command ,@(when mode
                                   `(:modes (cl:list (make-instance ,mode)))))
             ")"))))))

(defun %ncode-resolve-linkable-symbols (form)
  "Helper function for :NCODE tag.
Returns all the linkable symbols from FORM as multiple values:
- Function symbols.
- Variable symbols.
- Macro symbols.
- All the special forms (including some macros and functions needing extra care).
- All the strings that may potentially be resolvable with
  `nyxt:resolve-backtick-quote-links'."
  (let ((functions (list))
        (classes (list))
        (variables (list))
        (macros (list))
        (specials (list))
        (all-specials '(quote
                        flet labels symbol-macrolet macrolet
                        block catch eval-when progv lambda
                        progn prog1 unwind-protect tagbody setf setq multiple-value-prog1
                        let let* prog prog*
                        return-from throw the
                        multiple-value-call funcall apply
                        function
                        go locally))
        (linkable-strings (list)))
    (labels ((resolve-symbols-internal (form)
               (typecase form
                 (boolean nil)
                 (keyword nil)
                 (cons
                  (let ((first (first form)))
                    (alexandria:destructuring-case form
                      ;; More forms: def*, make-instance, slots, special forms?
                      ((make-instance class &rest args)
                       (push first functions)
                       (if (and (listp class)
                                (eq 'quote (first class)))
                           (push (second class) classes)
                           (resolve-symbols-internal class))
                       (resolve-symbols-internal args))
                      (((flet labels symbol-macrolet macrolet)
                        (&rest bindings) &body body)
                       (push first specials)
                       (mapcar (lambda (b)
                                 (resolve-symbols-internal (cddr b)))
                               bindings)
                       (mapc #'resolve-symbols-internal body))
                      (((block catch eval-when progv lambda) arg &body body)
                       (declare (ignore arg))
                       (push first specials)
                       (mapc #'resolve-symbols-internal body))
                      (((progn prog1 unwind-protect tagbody setf setq multiple-value-prog1)
                        &body body)
                       (push first specials)
                       (mapc #'resolve-symbols-internal body))
                      (((let let* prog prog*) (&rest bindings) &body body)
                       (push first specials)
                       (mapcar (alexandria:compose
                                #'resolve-symbols-internal #'second #'uiop:ensure-list)
                               bindings)
                       (mapc #'resolve-symbols-internal body))
                      (((return-from throw the) arg &optional value)
                       (declare (ignore arg))
                       (push first specials)
                       (resolve-symbols-internal value))
                      (((multiple-value-call funcall apply) function &rest args)
                       (push first specials)
                       (match function
                         ((list 'quote name)
                          (pushnew name functions))
                         ((list 'function name)
                          (pushnew name functions)))
                       (mapc #'resolve-symbols-internal args))
                      ((function value)
                       (push first specials)
                       (pushnew value functions))
                      (((go locally) &rest values)
                       (declare (ignore values))
                       (push first specials))
                      ((t &rest rest)
                       (cond
                         ((listp first)
                          (resolve-symbols-internal first)
                          (mapc #'resolve-symbols-internal rest))
                         ((member first all-specials)
                          (pushnew first specials))
                         ((and (symbolp first)
                               (nsymbols:macro-symbol-p first))
                          (pushnew first macros)
                          (let* ((arglist (uiop:symbol-call :nyxt :arglist first))
                                 (rest-position (or (position '&rest arglist)
                                                    (position '&body arglist))))
                            (if rest-position
                                (mapc #'resolve-symbols-internal (nthcdr rest-position rest))
                                (mapc #'resolve-symbols-internal rest))))
                         ((and (symbolp first)
                               (nsymbols:function-symbol-p first))
                          (pushnew first functions)
                          (mapc #'resolve-symbols-internal rest)))))))
                 (symbol
                  (when (nsymbols:variable-symbol-p form)
                    (pushnew form variables)))
                 (string
                  (pushnew form linkable-strings)))))
      (resolve-symbols-internal form)
      (values (set-difference functions all-specials) classes variables macros specials linkable-strings))))

(defun %ncode-prini (object package)
  "Custom `:ncode'-specific `nyxt:prini-string-string' with narrower margins."
  (nyxt:prini-to-string object :readably t :circle nil :right-margin 70 :package package))

(defun %ncode-htmlize-body (form package &optional (listing (%ncode-prini form package)))
  "Turn the FORM into an HTMLized rich text, augmented with `:nxref's to the used entities.
LISTING is the string to enrich, autogenerated from FORM on demand."
  (let ((*suppress-inserted-spaces* t)
        (*html-style* :tree)
        (*print-pretty* nil))
    (when (listp form)
      (multiple-value-bind (functions classes variables macros specials linkable-strings)
          (%ncode-resolve-linkable-symbols form)
        ;; We use \\s, because lots of Lisp symbols include non-word
        ;; symbols and would break if \\b was used.
        (macrolet ((replace-symbol-occurences (symbols type &key (prefix "(\\()") (suffix "(\\)|\\s)") (style :plain))
                     (alexandria:with-gensyms (sym sym-listing)
                       `(dolist (,sym ,symbols)
                          (when (search (%ncode-prini ,sym package) listing)
                            (let ((,sym-listing (%ncode-prini ,sym package)))
                              (setf listing
                                    (ppcre:regex-replace-all
                                     (uiop:strcat
                                      ,prefix (ppcre:quote-meta-chars ,sym-listing) ,suffix)
                                     listing
                                     (list
                                      0 ,(case style
                                           (:link `(with-html-string
                                                     (:nxref ,type ,sym ,sym-listing)))
                                           (:plain `(with-html-string
                                                      (:nxref :style "color: inherit; background-color: inherit;" ,type ,sym ,sym-listing)))
                                           (:span `(with-html-string
                                                     (:span.accent ,sym-listing))))
                                      1)))))))))
          (replace-symbol-occurences macros :macro :style :link)
          (replace-symbol-occurences functions :function :prefix "(\\(|#'|')")
          (replace-symbol-occurences classes :class-name :prefix "(')")
          (replace-symbol-occurences
           variables :variable :prefix "(\\s)" :suffix "(\\)|\\s)")
          (replace-symbol-occurences specials nil :style :span))
        (dolist (string linkable-strings)
          (setf listing (str:replace-all (%ncode-prini string package)
                                         (nyxt:resolve-backtick-quote-links string package)
                                         listing)))))
    listing))

(defun %ncode-htmlize-unless-string (form package)
  (typecase form
    (string form)
    (list (%ncode-htmlize-body form package))))

(defun %ncode-inline-p (body package)
  "BODY is only inline if it actually is a one-liner, literal or printed out."
  (and (serapeum:single body)
       (zerop (count #\newline
                     (if (stringp (first body))
                         (first body)
                         (%ncode-prini (first body) package))))))

;; TODO: Store the location it's defined in as a :title or link for discoverability?
;; FIXME: Maybe use :nyxt-user as the default package to not quarrel with REPL & config?
(deftag :ncode (body attrs &rest keys &key
                     (package :nyxt)
                     (inline-p nil inline-provided-p)
                     (repl-p t) (config-p t) (copy-p t)
                     file (editor-p file) (external-editor-p file)
                     &allow-other-keys)
  "Generate the <pre>/<code> listing from the provided Lisp BODY.

Forms in BODY should be quoted.

INLINE-P is about omitting newlines and <pre> tags---basically a <code> tag with
syntax highlighting and actions. If not provided, is determined automatically
based on BODY length.

Most *-P arguments mandate whether to add the buttons for:
- Editing the BODY in the built-in REPL (REPL-P).
- Appending the BODY to the auto-config.lisp (CONFIG-P).
- Copying the source to clipboard (COPY-P).
- Editing the FILE it comes from (if present), in
  - Nyxt built-in `nyxt/editor-mode:editor-mode' (EDITOR-P).
  - `nyxt:external-editor-program' (EXTERNAL-EDITOR-P)."
  (once-only (package)
    (with-gensyms (body-var inline-var file-var first plaintext htmlized)
      (let* ((keys keys)
             (*print-escape* nil)
             (id (nyxt:prini-to-string (gensym)))
             (select-options
               (append
                (when copy-p
                  `(((copy "Copy" "Copy the code to clipboard.")
                     (funcall (read-from-string "nyxt:ffi-buffer-copy")
                              (nyxt:current-buffer) ,plaintext))))
                (when config-p
                  `(((config
                      "Add to auto-config"
                      (format nil "Append this code to the auto-configuration file (~a)."
                              (nfiles:expand nyxt::*auto-config-file*)))
                     (alexandria:write-string-into-file
                      ,plaintext (nfiles:expand nyxt::*auto-config-file*)
                      :if-exists :append
                      :if-does-not-exist :create))))
                (when repl-p
                  `(((repl
                      "Try in REPL"
                      "Open this code in Nyxt REPL to experiment with it.")
                     (nyxt:buffer-load-internal-page-focus
                      (read-from-string "nyxt/repl-mode:repl")
                      :form ,plaintext))))
                (when (and file editor-p)
                  `(((editor
                      "Open in built-in editor"
                      "Open the file this code comes from in Nyxt built-in editor-mode.")
                     (funcall (read-from-string "nyxt/editor-mode:edit-file")
                              ,file-var))))
                (when (and file external-editor-p)
                  `(((external-editor
                      "Open in external editor"
                      "Open the file this code comes from in external editor.")
                     (uiop:launch-program
                      (append (funcall (read-from-string "nyxt:external-editor-program")
                                       (symbol-value (read-from-string "nyxt:*browser*")))
                              (list (uiop:native-namestring ,file-var)))))))))
             (select-code
               `(:nselect
                  :id ,id
                  :style (unless ,inline-var
                           "position: absolute; top: 0; right: 0; margin: 0; padding: 2PX")
                  ,@select-options)))
        (declare (ignorable keys))

        `(let* ((,body-var (list ,@body))
                (,first (first ,body-var))
                (,inline-var ,(if inline-provided-p
                                  inline-p
                                  `(%ncode-inline-p ,body-var ,package)))
                (,file-var ,file)
                (,plaintext (cond
                              ((and (serapeum:single ,body-var)
                                    (stringp ,first))
                               ,first)
                              ((serapeum:single ,body-var)
                               (%ncode-prini ,first ,package))
                              (t (str:join
                                  (make-string 2 :initial-element #\newline)
                                  (mapcar (lambda (f) (if (stringp f)
                                                          f
                                                          (%ncode-prini f ,package)))
                                          ,body-var)))))
                (,htmlized (if (serapeum:single ,body-var)
                               (%ncode-htmlize-unless-string ,first ,package)
                               (str:join
                                (make-string 2 :initial-element #\newline)
                                (mapcar (lambda (f) (%ncode-htmlize-unless-string f ,package)) ,body-var)))))
           (declare (ignorable ,plaintext ,file-var))
           ,(if inline-p
                `(:span (:code ,@attrs (:raw ,htmlized)) ,select-code)
                ;; https://spdevuk.com/how-to-create-code-copy-button/
                `(:div :style "position: relative"
                       (:pre ,@attrs ,select-code
                             (:code (:raw ,htmlized))))))))))

(deftag :nsection (body attrs &rest keys
                        &key (title (alexandria:required-argument 'title))
                        level
                        (open-p t)
                        (id (if (stringp title)
                                (str:remove-punctuation (str:downcase title) :replacement "-")
                                (alexandria:required-argument 'id)))
                        &allow-other-keys)
  "Collapsible and reference-able <section> with a neader.
TITLE should be a human-readable title for a section, or the form producing one.
LEVEL (if provided), is the level of heading for the section. If it's 2, the
heading is <h2>, if it's 3, then <h3> etc. If not provided, uses <h*> Spinneret
tag to intelligently guess the current heading level.
ID is the string identifier with which to reference the section elsewhere. Is
auto-generated from title by replacing all the punctuation and spaces with
hyphens, if not provided AND if the TITLE is a string.
OPEN-P mandates whether the section is collapsed or not. True (= not collapsed)
by default."
  (check-type level (or null (integer 2 6)))
  (let ((keys keys))
    (declare (ignorable keys))
    (with-gensyms (id-var)
      `(let ((spinneret::*html-path*
               ;; Push as many :section tags into the path, as necessary to imply
               ;; LEVEL for the sections inside this one. A trick on Spinneret to
               ;; make it think it's deeply nested already.
               (append
                spinneret::*html-path*
                (make-list ,(if level
                                `(1- (- ,level (spinneret::heading-depth)))
                                0)
                           :initial-element :section)))
             (,id-var ,id))
         (:section.section
          :id ,id-var
          (:details
           :open ,open-p
           (:summary
            (:header
             :style "display: inline"
             (:h* :style "display: inline"
               ,@attrs ,title)
             " " (:a.link :href (uiop:strcat "#" ,id-var) "#")))
           ,@body))))))

(deftag :nbutton (body attrs &rest keys &key (text (alexandria:required-argument 'text)) title buffer &allow-other-keys)
  "A Lisp-invoking button with TEXT text and BODY action.
Evaluates (via `nyxt/ps:lisp-eval') the BODY in BUFFER when clicked.
Forms in BODY can be unquoted, benefiting from the editor formatting."
  (let ((keys keys))
    (declare (ignorable keys))
    `(:button.button
      :onclick (ps:ps
                 (nyxt/ps:lisp-eval
                  (:title ,(or title text)
                          ,@(when buffer
                              (list :buffer buffer)))
                  ,@(mapcar #'remove-smart-quoting body)))
      ,@(when title
          (list :title title))
      ,@attrs
      ,text)))

(deftag :ninput (body attrs &rest keys &key rows cols onfocus onchange buffer &allow-other-keys)
  "Nicely styled <textarea> with a reasonable number of ROWS/COLS to accommodate the BODY.
Calls Lisp forms in ONFOCUS and ONCHANGE when one focuses and edits the input (respectively)."
  (let ((keys keys))
    (declare (ignorable keys))
    (once-only ((input-contents `(or (progn ,@(mapcar #'remove-smart-quoting body)) "")))
      `(:textarea.input
        :rows (or ,rows (1+ (count #\Newline ,input-contents)) 1)
        :cols (or ,cols (ignore-errors (apply #'max (mapcar #'length (str:lines ,input-contents)))) 80)
        ,@(when onfocus
            `(:onfocus (ps:ps (nyxt/ps:lisp-eval
                               (:title "ninput onfocus"
                                       ,@(when buffer
                                           (list :buffer buffer)))
                               ,onfocus))))
        ,@(when onchange
            ;; More events here.
            `(:onkeydown (ps:ps (nyxt/ps:lisp-eval
                                 (:title "ninput onchange/onkeydown"
                                         ,@(when buffer
                                             (list :buffer buffer)))
                                 ,onchange))))
        ,@attrs
        (:raw (the string ,input-contents))))))

(serapeum:-> %ntoc-create-toc ((integer 2 6) string) *)
(defun %ntoc-create-toc (depth body)
  "Generate the code for the table of contents based on string BODY."
  (labels ((parent-section (elem)
             (find-if #'nyxt/dom:section-element-p (nyxt/dom:parents elem)))
           (format-section (heading level)
             (with-html-string
               (let ((parent-section (parent-section heading)))
                 (:li (:a :href (format nil "#~a" (plump:attribute parent-section "id"))
                          (plump:text heading)))
                 (serapeum:and-let* ((_ (< level depth))
                                     (inner-level (1+ level))
                                     (inner-headers
                                      (clss:ordered-select (format nil "h~a" inner-level) parent-section)))
                   (:ul (loop for inner-header across inner-headers
                              collect (:raw (format-section inner-header inner-level)))))))))
    (let* ((dom (nyxt/dom:named-html-parse body))
           (h2s (clss:ordered-select "h2" dom)))
      (with-html-string
        (loop for h2 across h2s
              collect (:ul (:raw (format-section h2 2))))))))

(deftag :ntoc (body attrs &rest keys &key (title "Table of contents") (depth 3) &allow-other-keys)
  "Generate table of contents for BODY up to DEPTH.
Looks for section tags with ID-s to link to.
:nsection sections are perfectly suitable for that."
  (let ((keys keys))
    (declare (ignorable keys))
    (with-gensyms (body-var)
      `(let ((,body-var (with-html-string ,@body)))
         (:nav#toc
          ,@attrs
          (:nsection
            :title ,title
            (:raw (%ntoc-create-toc ,depth ,body-var))))
         (:raw ,body-var)))))
