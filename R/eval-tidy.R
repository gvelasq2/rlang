#' Tidy evaluation
#'
#' @description
#'
#' Tidy evaluation is the tidyverse's conception of how to create
#' domain-specific languages. The most prominent examples of such
#' sublanguages in R are modelling specifications with formulas
#' (`lm()`, `lme4::lmer()`, etc) and data manipulation grammars
#' (dplyr, tidyr). Most of these DSLs put dataframe columns in scope
#' so that users can refer to them directly, saving keystrokes during
#' interactive analysis and creating easily readable code.
#'
#' R makes it easy to create DSLs thanks to three features of the
#' language:
#'
#' - R code is first-class. That is, R code can be manipulated like
#'   any other object (see [sym()], [lang()] and [node()] for creating
#'   such objects). We also call _expressions_ these objects
#'   containing R code (see [is_expr()]).
#'
#' - Scope is first-class. Scope is the lexical environment that
#'   associates values to symbols in expressions. Environments can be
#'   created (see [env()]) and manipulated as regular objects.
#'
#' - Finally, functions can capture the expressions that were supplied
#'   as arguments instead of being passed the value of these
#'   expressions (see [enquo()] and [enexpr()]).
#'
#' To sum up, R functions can capture expressions, manipulate them
#' like regular objects, and alter the meaning of symbols referenced
#' in these expressions by changing the scope (the environment) upon
#' evaluation. This combination of features allow R packages to change
#' the meaning of R code and create domain-specific sublanguages.
#'
#' Tidy evaluation is an opinionated approach over how to use these
#' features to create consistent DSLs. The main principle is that
#' sublanguages should feel and behave like R code. They change the
#' meaning of R code, but only in a precise and circumscribed way,
#' behaving otherwise predictably and in accordance with R
#' semantics. As a result, users are be able to leverage their
#' existing knowledge of R programming to solve problems involving the
#' sublanguage in ways that were not necessarily envisioned or planned
#' by their designers.
#'
#' @section Parsing versus evaluation:
#'
#' There are two ways of dealing with unevaluated expressions to
#' create a sublanguage. The first is to parse the expression
#' manually, the other is to evaluate the expression in a modified
#' environment.
#'
#' Let's take the example of designing a modelling DSL to illustrate
#' parsing. You would need to traverse the call and analyse all
#' functions encountered in the expression (in particular, operators
#' like `+` or `:`), building a data structure describing a model as
#' you go. This method of dealing with expressions is tedious, rigid
#' and error prone because you're basically rewriting an interpreter
#' of R code. It is extremely difficult to emulate R semantics when
#' parsing an expression: does a function take arguments by value or
#' by expression? Can I parse these arguments? Do these symbols mean
#' the same thing in this context? Will this argument be evaluated
#' immediately or later on lazily? Given the difficulty of getting it
#' right, parsing should be a last resort.
#'
#' The second way is to rely on evaluation in a specific environment.
#' The expression is evaluated in an environment where certain objects
#' and functions are given special definitions. For instance `+` might
#' be defined as accumulating vectors in a data structure to build a
#' design matrix later on, or we might put helper functions in scope
#' (an example is `dplyr::select()`). As this method is relying on the
#' R interpreter, the grammar is much more likely to behave like real
#' R code.
#'
#' R DSLs are traditionally implemented with a mix of both
#' principles. Expressions are parsed in ad hoc ways, but are
#' eventually evaluated in an environment containing dataframe
#' columns. While it is difficult to completely avoid ad hoc parsing,
#' tidyeval DSLs strive to rely on evaluation as much as possible.
#'
#' @section Values versus expressions:
#'
#' A corollary of emphasising evaluation is that your DSL functions
#' should understand _values_ in addition to expressions. This is
#' especially important with [quasiquotation]: users can bypass
#' symbolic evaluation completely by unquoting values. For instance,
#' the following expressions are completely equivalent:
#'
#' ```
#' # Taking an expression:
#' dplyr::mutate(mtcars, cyl2 = cyl * 2)
#'
#' # Taking a value:
#' var <- mtcars$cyl * 2
#' dplyr::mutate(mtcars, cyl2 = !! var)
#' ```
#'
#' `dplyr::mutate()` evaluates expressions in a context where
#' dataframe columns are in scope, but it accepts any value that can
#' be treated as a column (a recycled scalar or a vector as long as
#' there are rows).
#'
#' A more complex example is `dplyr::select()`. This function
#' evaluates dataframe columns in a context where they represent
#' column positions. Therefore, `select()` understands column symbols
#' like `cyl`:
#'
#' ```
#' # Taking a symbol:
#' dplyr::select(mtcars, cyl)
#'
#' # Taking an unquoted symbol:
#' var <- quote(sym)
#' dplyr::select(mtcars, !! var)
#' ```
#'
#' But it also understands column positions:
#'
#' ```
#' # Taking a column position:
#' dplyr::select(mtcars, 2)
#'
#' # Taking an unquoted column position:
#' var <- 2
#' dplyr::select(mtcars, !! var)
#' ```
#'
#' Understanding values in addition to expressions makes your grammar
#' more consistent, predictable, and programmable.
#'
#' @section Tidy scoping:
#'
#' The special type of scoping found in R grammars implemented with
#' evaluation poses some challenges. Both objects from a dataset and
#' objects from the current environment should be in scope, with the
#' former having precedence over the latter. In other words, the
#' dataset should _overscope_ the dynamic context. The traditional
#' solution to this issue in R is to transform a dataframe to an
#' environment and set the calling frame as the parent environment.
#' This way, the symbols appearing in the expression can refer to
#' their surrounding context in addition to dataframe columns. In
#' other words, the grammar implements correctly an important aspect
#' of R: [lexical scoping](http://adv-r.had.co.nz/Functions.html#lexical-scoping).
#'
#' Creating this scope hierarchy (data first, context next) is
#' possible because R makes it easy to capture the calling environment
#' (see [caller_env()]). However, this supposes that captured
#' expressions were actually typed in the most immediate caller
#' frame. This assumption easily breaks in R. First because
#' quasiquotation allows an user to combine expressions that do not
#' necessarily come from the same lexical context. Secondly because
#' arguments can be forwarded through the special `...` argument.
#' While base R does not provide any way of capturing a forwarded
#' argument along with its original environment, rlang features
#' [quos()] for this purpose. This function looks up each forwarded
#' arguments and returns a list of [quosures][quo] that bundle the
#' expressions with their own dynamic environments.
#'
#' In that context, maintaining scoping consistency is a challenge
#' because we're dealing with multiple environments, one for each
#' argument plus one containing the overscoped data. This creates
#' difficulties regarding tidyeval's overarching principle that we
#' should change R semantics through evaluation. It is possible to
#' evaluate each expression in turn, but how can we combine all
#' expressions into one and evaluate it tidily at once? An expression
#' can only be evaluated in a single environment. This is where
#' quosures come into play.
#'
#' @section Quosures and overscoping:
#'
#' Unlike formulas, [quosures][quo] aren't simple containers of an
#' expression and an environment. In the tidyeval framework, they have
#' the property of self-evaluating in their own environment. Hence
#' they can appear anywhere in an expression (e.g. by being
#' [unquoted][quasiquotation]), carrying their own environment and
#' behaving otherwise exactly like surrounding R code. Quosures behave
#' like reified
#' [promises](http://adv-r.had.co.nz/Computing-on-the-language.html#capturing-expressions)
#' that are unreified during tidy evaluation.
#'
#' However, the dynamic environments of quosures do not contain
#' overscoped data. It's not of much use for sublanguages to get the
#' contextual environment right if they can't also change the meaning
#' of code quoted in quosures. To solve this issue, tidyeval rechains
#' the overscope to a quosure just before it self-evaluates. This way,
#' both the lexical environment and the overscoped data are in scope
#' when the quosure is evaluated. Is is evaluated tidily.
#'
#' In practical terms, `eval_tidy()` takes a `data` argument and
#' creates an overscope suitable for tidy evaluation. In particular,
#' these overscopes contain definitions for self-evaluation of
#' quosures. See [eval_tidy_()] and [as_overscope] for more flexible
#' ways of creating overscopes.
#'
#' @section Theory:
#'
#' The most important concept of the tidy evaluation framework is that
#' expressions should be scoped in their dynamic context. This issue
#' is linked to the computer science concept of _hygiene_, which
#' roughly means that symbols should be scoped in their local context,
#' the context where they are typed by the user. In a way, hygiene is
#' what "tidy" refers to in "tidy evaluation".
#'
#' In languages with macros, hygiene comes up for [macro
#' expansion](https://en.wikipedia.org/wiki/Hygienic_macro). While
#' macros look like R's non-standard evaluation functions, and share
#' certain concepts with them (in particular, they get their arguments
#' as unevaluated code), they are actually quite different. Macros are
#' compile-time and therefore can only operate on code and constants,
#' never on user data. They also don't return a value but are expanded
#' in place by the compiler. In comparison, R does not have macros but
#' it has [fexprs](https://en.wikipedia.org/wiki/Fexpr), i.e. regular
#' functions that get arguments as unevaluated expressions rather than
#' by their value (fexprs are what we call NSE functions in the R
#' community). Unlike macros, these functions execute at run-time and
#' return a value.
#'
#' Symbolic hygiene is a problem for macros during expansion because
#' expanded code might invisibly redefine surrounding symbols.
#' Correspondingly, hygiene is an issue for NSE functions if the code
#' they captured gets evaluated in the wrong
#' environment. Historically, fexprs did not have this problem because
#' they existed in languages with dynamic scoping. However in modern
#' languages with lexical scoping, it is imperative to bundle quoted
#' expressions with their dynamic environment. The most natural way
#' to do this in R is to use formulas and quosures.
#'
#' While formulas were introduced in the S language, the quosure was
#' invented much later for R [by Luke Tierney in
#' 2000](https://github.com/wch/r-source/commit/a945ac8e6a82617205442d44a2be3a497d2ac896).
#' From that point on formulas recorded their environment along with
#' the model terms. In the Lisp world, the Kernel Lisp language also
#' recognised that arguments should be captured together with their
#' dynamic environment in order to solve hygienic evaluation in the
#' context of lexically scoped languages (see chapter 5 of [John
#' Schutt's thesis](https://web.wpi.edu/Pubs/ETD/Available/etd-090110-124904/)).
#' However, Kernel Lisp did not have quosures and avoided quotation or
#' quasiquotation operators altogether to avoid scoping issues.
#'
#' Tidyeval's contributes to the problem of hygienic evaluation in
#' four ways:
#'
#' - Promoting the quosure as the proper quotation data structure, in
#'   order to keep track of the dynamic environment of quoted
#'   expressions.
#'
#' - Introducing systematic quasiquotation in all capturing functions
#'   in order to make it straightforward to program with these
#'   functions.
#'
#' - Treating quosures as reified promises that self-evaluate within
#'   their own environments. This allows unquoting quosures within
#'   other quosures, which is the key for programming hygienically
#'   with capturing functions.
#'
#' - Building a moving overscope that rechains to quosures as they get
#'   evaluated. This makes it possible to change the evaluation
#'   context and at the same time take the lexical context of each
#'   quosure into account.
#'
#' @name tidy-evaluation
#' @seealso [eval_tidy()], [quo()], [quasiquotation].
NULL

#' Evaluate an expression tidily
#'
#' @description
#'
#' `eval_tidy()` is a variant of [base::eval()] and [eval_bare()] that
#' powers the [tidy evaluation framework][tidy-evaluation]. It
#' evaluates `expr` in an [overscope][as_overscope] where the special
#' definitions enabling tidy evaluation are installed. This enables
#' the following features:
#'
#' - Overscoped data. You can supply a data frame or list of named
#'   vectors to the `data` argument. The data contained in this list
#'   has precedence over the objects in the contextual environment.
#'   This is similar to how [base::eval()] accepts a list instead of
#'   an environment.
#'
#' - Self-evaluation of quosures. Within the overscope, quosures act
#'   like promises. When a quosure within an expression is evaluated,
#'   it automatically invokes the quoted expression in the captured
#'   environment (chained to the overscope). Note that quosures do not
#'   always get evaluated because of lazy semantics, e.g. `TRUE ||
#'   ~never_called`.
#'
#' - Pronouns. `eval_tidy()` installs the `.env` and `.data`
#'   pronouns. `.env` contains a reference to the calling environment,
#'   while `.data` refers to the `data` argument. These pronouns lets
#'   you be explicit about where to find values and throw errors if
#'   you try to access non-existent values.
#'
#' @param expr An expression.
#' @param data A list (or data frame). This is passed to the
#'   [as_dictionary()] coercer, a generic used to transform an object
#'   to a proper data source. If you want to make `eval_tidy()` work
#'   for your own objects, you can define a method for this generic.
#' @param env The lexical environment in which to evaluate `expr`.
#' @seealso [tidy-evaluation], [quo()], [quasiquotation]
#' @export
#' @examples
#' # Like base::eval() and eval_bare(), eval_tidy() evaluates quoted
#' # expressions:
#' expr <- expr(1 + 2 + 3)
#' eval_tidy(expr)
#'
#' # Like base::eval(), it lets you supply overscoping data:
#' foo <- 1
#' bar <- 2
#' expr <- quote(list(foo, bar))
#' eval_tidy(expr, list(foo = 100))
#'
#' # The main difference is that quosures self-evaluate within
#' # eval_tidy():
#' quo <- quo(1 + 2 + 3)
#' eval(quo)
#' eval_tidy(quo)
#'
#' # Quosures also self-evaluate deep in an expression not just when
#' # directly supplied to eval_tidy():
#' expr <- expr(list(list(list(!! quo))))
#' eval(expr)
#' eval_tidy(expr)
#'
#' # Self-evaluation of quosures is powerful because they
#' # automatically capture their enclosing environment:
#' foo <- function(x) {
#'   y <- 10
#'   quo(x + y)
#' }
#' f <- foo(1)
#'
#' # This quosure refers to `x` and `y` from `foo()`'s evaluation
#' # frame. That's evaluated consistently by eval_tidy():
#' f
#' eval_tidy(f)
#'
#'
#' # Finally, eval_tidy() installs handy pronouns that allows users to
#' # be explicit about where to find symbols. If you supply data,
#' # eval_tidy() will look there first:
#' cyl <- 10
#' eval_tidy(quo(cyl), mtcars)
#'
#' # To avoid ambiguity and be explicit, you can use the `.env` and
#' # `.data` pronouns:
#' eval_tidy(quo(.data$cyl), mtcars)
#' eval_tidy(quo(.env$cyl), mtcars)
#'
#' # Note that instead of using `.env` it is often equivalent to
#' # unquote a value. The only difference is the timing of evaluation
#' # since unquoting happens earlier (when the quosure is created):
#' eval_tidy(quo(!! cyl), mtcars)
#' @name eval_tidy
eval_tidy <- function(expr, data = NULL, env = caller_env()) {
  if (is_list(expr)) {
    return(map(expr, eval_tidy, data = data))
  }

  if (!inherits(expr, "quosure")) {
    expr <- new_quosure(expr, env)
  }
  overscope <- as_overscope(expr, data)
  on.exit(overscope_clean(overscope))

  overscope_eval_next(overscope, expr)
}

#' Data pronoun for tidy evaluation
#'
#' This pronoun is installed by functions performing [tidy
#' evaluation][eval_tidy]. It allows you to refer to overscoped data
#' explicitly.
#'
#' You can import this object in your package namespace to avoid `R
#' CMD check` errors when referring to overscoped objects.
#'
#' @name tidyeval-data
#' @export
#' @examples
#' quo <- quo(.data$foo)
#' eval_tidy(quo, list(foo = "bar"))
.data <- NULL
delayedAssign(".data", as_dictionary(list(), read_only = TRUE))

#' Tidy evaluation in a custom environment.
#'
#' We recommend using [eval_tidy()] in your DSLs as much as possible
#' to ensure some consistency across packages (`.data` and `.env`
#' pronouns, etc). However, some DSLs might need a different
#' evaluation environment. In this case, you can call `eval_tidy_()`
#' with the bottom and the top of your custom overscope (see
#' [as_overscope()] for more information).
#'
#' Note that `eval_tidy_()` always installs a `.env` pronoun in the
#' bottom environment of your dynamic scope. This pronoun provides a
#' shortcut to the original lexical enclosure (typically, the dynamic
#' environment of a captured argument, see [enquo()]). It also
#' cleans up the overscope after evaluation. See [overscope_eval_next()]
#' for evaluating several quosures in the same overscope.
#'
#' @inheritParams eval_tidy
#' @inheritParams as_overscope
#' @export
eval_tidy_ <- function(expr, bottom, top = NULL, env = caller_env()) {
  top <- top %||% bottom
  overscope <- new_overscope(bottom, top)
  on.exit(overscope_clean(overscope))

  if (!inherits(expr, "quosure")) {
    expr <- new_quosure(expr, env)
  }
  overscope_eval_next(overscope, expr)
}


#' Create a dynamic scope for tidy evaluation.
#'
#' Tidy evaluation works by rescoping a set of symbols (column names
#' of a data frame for example) to custom bindings. While doing this,
#' it is important to keep the original environment of captured
#' expressions in scope. The gist of tidy evaluation is to create a
#' dynamic scope containing custom bindings that should have
#' precedence when expressions are evaluated, and chain this scope
#' (set of linked environments) to the lexical enclosure of formulas
#' under evaluation. During tidy evaluation, formulas are transformed
#' into formula-promises and will self-evaluate their RHS as soon as
#' they are called. The main trick of tidyeval is to consistently
#' rechain the dynamic scope to the lexical enclosure of each tidy
#' quote under evaluation.
#'
#' These functions are useful for embedding the tidy evaluation
#' framework in your own DSLs with your own evaluating function. They
#' let you create a custom dynamic scope. That is, a set of chained
#' environments whose bottom serves as evaluation environment and
#' whose top is rechained to the current lexical enclosure. But most
#' of the time, you can just use [eval_tidy_()] as it will take
#' care of installing the tidyeval components in your custom dynamic
#' scope.
#'
#' * `as_overscope()` is the function that powers [eval_tidy()]. It
#'   could be useful if you cannot use `eval_tidy()` for some reason,
#'   but serves mostly as an example of how to build a dynamic scope
#'   for tidy evaluation. In this case, it creates pronouns `.data`
#'   and `.env` and buries all dynamic bindings from the supplied
#'   `data` in new environments.
#'
#' * `new_overscope()` is called by `as_overscope()` and
#'   [eval_tidy_()]. It installs the definitions for making
#'   formulas self-evaluate and for formula-guards. It also installs
#'   the pronoun `.top_env` that helps keeping track of the boundary
#'   of the dynamic scope. If you evaluate a tidy quote with
#'   [eval_tidy_()], you don't need to use this.
#'
#' * `eval_tidy_()` is useful when you have several quosures to
#'   evaluate in a same dynamic scope. That's a simple wrapper around
#'   [eval_bare()] that updates the `.env` pronoun and rechains the
#'   dynamic scope to the new formula enclosure to evaluate.
#'
#' * Once an expression has been evaluated in the tidy environment,
#'   it's a good idea to clean up the definitions that make
#'   self-evaluation of formulas possible `overscope_clean()`.
#'   Otherwise your users may face unexpected results in specific
#'   corner cases (e.g. when the evaluation environment is leaked, see
#'   examples). Note that this function is automatically called by
#'   [eval_tidy_()].
#'
#' @param quo A [quosure].
#' @param data Additional data to put in scope.
#' @return An overscope environment.
#' @export
#' @examples
#' # Evaluating in a tidy evaluation environment enables all tidy
#' # features:
#' expr <- quote(list(.data$cyl, ~letters))
#' f <- as_quosure(expr)
#' overscope <- as_overscope(f, data = mtcars)
#' overscope_eval_next(overscope, f)
#'
#' # However you need to cleanup the environment after evaluation.
#' # Otherwise the leftover definitions for self-evaluation of
#' # formulas might cause unexpected results:
#' fn <- overscope_eval_next(overscope, ~function() ~letters)
#' fn()
#'
#' overscope_clean(overscope)
#' fn()
as_overscope <- function(quo, data = NULL) {
  data_src <- as_dictionary(data, read_only = TRUE)
  enclosure <- f_env(quo) %||% base_env()

  # Create bottom environment pre-chained to the lexical scope
  bottom <- child_env(enclosure)

  # Emulate dynamic scope for established data
  if (is_vector(data)) {
    bottom <- env_bury(bottom, !!! discard_unnamed(data))
  } else if (is_env(data)) {
    bottom <- env_clone(data, parent = bottom)
  } else if (!is_null(data)) {
    abort("`data` must be a list or an environment")
  }

  # Install data pronoun
  bottom$.data <- data_src

  new_overscope(bottom, enclosure = enclosure)
}

#' @rdname as_overscope
#' @param bottom This is the environment (or the bottom of a set of
#'   environments) containing definitions for overscoped symbols. The
#'   bottom environment typically contains pronouns (like `.data`)
#'   while its direct parents contain the overscoping bindings. The
#'   last one of these parents is the `top`.
#' @param top The top environment of the overscope. During tidy
#'   evaluation, this environment is chained and rechained to lexical
#'   enclosures of self-evaluating formulas (or quosures). This is the
#'   mechanism that ensures hygienic scoping: the bindings in the
#'   overscope have precedence, but the bindings in the dynamic
#'   environment where the tidy quotes were created in the first place
#'   are in scope as well.
#' @param enclosure The default enclosure. After a quosure is done
#'   self-evaluating, the overscope is rechained to the default
#'   enclosure.
#' @return A valid overscope: a child environment of `bottom`
#'   containing the definitions enabling tidy evaluation
#'   (self-evaluating quosures, formula-unguarding, ...).
#' @export
new_overscope <- function(bottom, top = NULL, enclosure = base_env()) {
  top <- top %||% bottom

  # Create a child because we don't know what might be in bottom_env.
  # This way we can just remove all bindings between the parent of
  # `overscope` and `overscope_top`. We don't want to clean everything in
  # `overscope` in case the environment is leaked, e.g. through a
  # closure that might rely on some local bindings installed by the
  # user.
  overscope <- child_env(bottom)

  overscope$`~` <- f_self_eval(overscope, top)
  overscope$.top_env <- top
  overscope$.env <- enclosure

  overscope
}
#' @rdname as_overscope
#' @param overscope A valid overscope containing bindings for `~`,
#'   `.top_env` and `_F` and whose parents contain overscoped bindings
#'   for tidy evaluation.
#' @param env The lexical enclosure in case `quo` is not a validly
#'   scoped quosure. This is the [base environment][base_env] by
#'   default.
#' @export
overscope_eval_next <- function(overscope, quo, env = base_env()) {
  quo <- as_quosureish(quo, env)
  lexical_env <- f_env(quo)

  overscope$.env <- lexical_env
  mut_parent_env(overscope$.top_env, lexical_env)

  .Call(rlang_eval, f_rhs(quo), overscope)
}
#' @rdname as_overscope
#' @export
overscope_clean <- function(overscope) {
  cur_env <- env_parent(overscope)
  top_env <- overscope$.top_env %||% cur_env

  # At this level we only want to remove what we have installed
  env_unbind(overscope, c("~", ".top_env", ".env"))

  while(!identical(cur_env, env_parent(top_env))) {
    env_unbind(cur_env, names(cur_env))
    cur_env <- env_parent(cur_env)
  }

  overscope
}

#' @useDynLib rlang rlang_set_parent
f_self_eval <- function(overscope, overscope_top) {
  function(...) {
    f <- sys.call()

    if (!inherits(f, "quosure")) {
      # We want formulas to be evaluated in the overscope so that
      # functions like case_when() can pick up overscoped data. Using
      # the parent because the bottom level has definitions for
      # quosure self-evaluation etc.
      return(eval_bare(f, env_parent(overscope)))
    }
    if (quo_is_missing(f)) {
      return(missing_arg())
    }

    # Swap enclosures temporarily by rechaining the top of the
    # dynamic scope to the enclosure of the new formula, if it has
    # one. We do it at C level to avoid GC adjustments when changing
    # the parent. This should be safe since we reset everything
    # afterwards.
    .Call(rlang_set_parent, overscope_top, f_env(f) %||% overscope$.env)
    on.exit(.Call(rlang_set_parent, overscope_top, overscope$.env))

    .Call(rlang_eval, f_rhs(f), overscope)
  }
}