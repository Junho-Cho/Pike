#pike __REAL_VERSION__

// Incremental Pike Evaluator
//
// $Id: Hilfe.pmod,v 1.26 2002/02/20 01:11:15 nilsson Exp $

constant hilfe_todo = #"List of known Hilfe bugs/room for improvements:

- Hilfe can not handle sscanf statements like
  int a = sscanf(\"12\", \"%d\", int b);
- Hilfe can not handle enums.
- Hilfe can not handle typedefs.
- Hilfe can not handle generated types, e.g.
  constant boolean = typeof(0)|typeof(1); boolean flag = 1;
- Hilfe should possibly handle imports better, e.g. overwrite the
  local variables/constants/functions/programs.
- Some preprocessor stuff works. Some doesn't. They should be
  reviewed and fixed where possible.
- Parser.Pike needs to stream better. Currently Hilfe input that
  ends with /* or #\"will produce a tokianization error since the
  end of that token can not be found.
- Filter exit/quit from history. Could be done by adding a 'pop'
  method to Readline.History and call it from StdinHilfes' destroy.
- Make Hilfe thread safe (Move ___Hilfe and ___hilfe to the
  resolver in the compiler object).
- Remove tokens_to_code kludge, either by fixing Parser.Pike so
  that it returns the correct tokens, or by fixing Pike so that
  \"( < > )\" is a valid statement.
- Make it possible to easily change history size, e.g.
  \"set history 5\".
- Make it possible to easily change result format, e.g.
  \"set resultformat %[1]O (%[0]d)\".
- Make it possible to quickly undefine variables, e.g. \"reset a\".
- Add some better multiline edit support.
- Tab completion of variable and module names.
";


//
// Built in commands
//

private void|string command_exit(int|Evaluator e, void|string line, void|array(string) tokens) {
  if(intp(e)) return "Exit Hilfe.";
  e->write("Exiting.\n");
  destruct(e);
  exit(0);
}

private void|string command_help(int|Evaluator e, void|string line, void|array(string) tokens) {
  if(intp(e)) return "Show help text.";
  line = tokens[2..sizeof(tokens)-2]*"";
  function write = e->write;

  if(line == "me more") {
    write( #"Some commands has extended help available. This can be displayed by
typing help followed by the name of the command, e.g. \"help dump\".
Commands clobbered by e.g. variable declarations can be reached by
prefixing a dot to the command, e.g. \".exit\".

A history of the last returned results are kept and can be accessed
from your hilfe expressions with the variable __. You can either
\"address\" your results with absolute addresses, e.g. __[2] to get
the second result ever, or with relative addresses, e.g. __[-1] to
get the last result. The last result is also available in the
variable _, thus _==__[-1] is true. The magic _ and __ variable can
be clobbered with local definitions to disable them, e.g. by typing
\"int _;\". The result history is currently ten entries long.

A history of the 512 last entered lines is kept in Hilfe. You can
browse this list with your arrow keys up/down. When you exit Hilfe
your history will be saved in .hilfe_history in the directory set
in environment variable $HOME or $USERPROFILE. Next time hilfe is
started the history is imported.

You can put a .hilferc file at the directory set in your
environment variable $HOME or $USERPROFILE. The contents of this
file will be evaulated in hilfe during each startup.

Note that there are a few symbols that you can not define, since
they are used by Hilfe. They are:

___hilfe         A mapping containing all defined symbols.
___Hilfe         The Hilfe object.
___HilfeWrapper  A wrapper around the entered expression.


Type \"help hilfe todo\" to get a list of known Hilfe bugs/lackings.
");
    return;
  }

  if(line == "hilfe todo") {
    write(hilfe_todo);
    return;
  }

  mapping(string:function|object) commands =
    e->commands - (["hej":0, "look":0]);

  if(line && commands[line]) {
    write(commands[line](1)+"\n");
    return;
  }

  write("\n");
  e->print_version();
  write( #"Hilfe is a tool to evaluate Pike interactively and incrementally.
Any Pike function, expression or variable declaration can be
entered at the command line. There are also a few extra commands:

");

  array err = ({});
  foreach(sort(indices(commands)), string cmd)
    err += ({ catch(write(" %-10s - %s\n", cmd, e->commands[cmd]())) });

  write( #" .          - Abort current input batch.

Enter \"help me more\" for further Hilfe help.
");

  foreach(err-({0}), mixed err)
    write(describe_backtrace(err)+"\n\n");
}

private object command_dump = class {

    private function write;

    private string help() {
      return #"dump
      Shows the currently defined constants, variables, functions
      and programs. It also lists all active inherits ans imports.

dump history
      Shows all items in the history queue.

dump state
      Shows the current parser state. Only useful for debugging
      Hilfe.

dump wrapper
      Show the latest Hilfe wrapper that the last expression was
      evaulated in. Useful when debugging Hilfe (i.e. investigating
      why valid Pike expressions doesn't compile).";
    }

    private void wrapper(Evaluator e) {
      if(!e->last_compiled_expr) {
	write("No wrapper compiled so far.\n");
	return;
      }
      write("Last compiled wrapper:\n");
      write(e->last_compiled_expr);
    }

    private void history(Evaluator e) {
      e->history->show_history();
      return;
    }

    private string print_mapping(array(string) ind, array val) {
      int m = max( @filter(map(ind, sizeof), `<, 20), 8 );
      int i;
      foreach(ind, string name)
	write("%-*s : %s\n", m, name, replace(sprintf("%O", val[i++]), "\n", "\n"+(" "*m)+"   "));
    }

    private void dump(Evaluator e) {
      if(sizeof(e->constants)) {
	write("\nConstants:\n");
	array a=indices(e->constants), b=values(e->constants);
	sort(a,b);
	print_mapping(a,b);
      }
      if(sizeof(e->variables)) {
	write("\nVariables:\n");
	array a=indices(e->variables), b=values(e->variables);
	sort(a,b);
	a = map(a, lambda(string in) { return e->types[in] + " " + in; } );
	print_mapping(a,b);
      }
      if(sizeof(e->functions)) {
	write("\nFunctions:\n");
	foreach(sort(indices(e->functions)), string name)
	  write("%s\n", name);
      }
      if(sizeof(e->programs)) {
	write("\nPrograms:\n");
	foreach(sort(indices(e->programs)), string name)
	  write("%s\n", name);
      }
      if(sizeof(e->inherits)) {
	write("\nInherits:\n" + e->inherits*"\n" + "\n");
      }
      if(sizeof(e->imports)) {
	write("\nImports:\n" + e->imports*"\n" + "\n");
      }
    }

    void|string `()(int|Evaluator e, void|string line, void|array(string) tokens) {
      if(!e) return "Dump variables and other info.";
      write = e->write;
      if(e==1) return help();

      line = tokens[2..sizeof(tokens)-2]*"";
      switch( line ) {
      case "wrapper":
	wrapper(e);
	return;
      case "state":
	e->state->show_state();
	return;
      case "history":
	history(e);
	return;
      case 0:
	dump(e);
	return;
      }
      write("Unknown dump specifier.\n");
      write(help()+"\n");
    }
  }();

private void|string command_new(int|Evaluator e, void|string line, void|array(string) tokens) {
  if(!e) return "Clears the Hilfe state.";
  if(e==1) return #"
Clears the current Hilfe state. This includes the parser state,
variables, constants, functions, programs, inherits, imports and
the history. It does not include the currently installed commands.
Note that code in your .hilferc will not be reevaluated.";
  e->reset_evaluator();
}


//
// Support stuff..
//

private constant whitespace = (< ' ', '\n' ,'\r', '\t' >);
private constant termblock = (< "catch", "do", "gauge", "lambda" >);
private constant modifier = (< "extern", "final", "inline", "local", "nomask",
			       "optional", "private", "protected", "public",
			       "static", "variant" >);

//! In every Hilfe object (@[Evaluator]) there is a ParserState object
//! that manages the current state of the parser. Essentially tokens are
//! entered in one end and complete expressions is outputted in the other.
//! The parser object is accessible as ___Hilfe->state from Hilfe expressions.
private class ParserState {
  private ADT.Stack pstack = ADT.Stack();
  private constant starts = ([ ")":"(", "}":"{", "]":"[",
			       ">)":"(<", "})":"({", "])":"([" ]);
  private array(string) pipeline = ({ });
  private array(array(string)) ready = ({ });
  private string last;
  private string block;

  //! Feed more tokens into the state.
  void feed(array(string) tokens) {
    foreach(tokens, string token) {
      if(sizeof(token)>1 && (token[0..1]=="//" || token[0..1]=="/*")) continue; // comments

      // If we start a block at the uppermost level, what kind of block is it?
      if(token=="{" && !pstack->ptr && !block)
	block = last;
      if( (token=="lambda" || token=="class") && !pstack->ptr)
	block = token;

      // Do we begin any kind of parenthesis level?
      if(token=="(" || token=="{" || token=="[" ||
	 token=="(<" || token=="({" || token=="([")
	pstack->push(token);

      // Do we end any king of parenthesis level?
      if(token==")" || token=="}" || token=="]" ||
	 token==">)" || token=="})" || token=="])" ) {
	if(!pstack->ptr)
	   throw(sprintf("%O end parenthesis without start parenthesis.", token));
	if(pstack->top()!=starts[token])
	   throw(sprintf("%O end parenthesis does not match closest start parenthesis %O.",
			 token, pstack->top()));
	pstack->pop();
      }

      pipeline += ({ token });

      // expressions
      if(token==";" && !pstack->ptr) {
	ready += ({ pipeline });
	pipeline = ({});
      }

      // If we end a block at the uppermost level, and it doesn't need a ";",
      // then we can move out that block of the pipeline.
      if(token=="}" && !pstack->ptr && !termblock[block]) {
	ready += ({ pipeline });
	pipeline = ({});
	block = 0;
      }

      if(!whitespace[token[0]])
	last = token;
    }
  }

  //! Read out completed expressions. Returns an array where every element
  //! is an expression represented as an array of tokens.
  array(array(string)) read() {
    array ret = ready;
    ready = ({});
    return ret;
  }

  //! Returns true if there is any waiting expression that can be fetched
  //! with @[read].
  int datap() {
    return sizeof(ready);
  }

  //! Are we in the middle of an expression. Used e.g. for chaning the
  //! Hilfe prompt when entering multiline expressions.
  int(0..1) finishedp() {
    if(pstack->ptr) return 0;
    if(!sizeof(pipeline)) return 1;
    if(sizeof(pipeline)==1 && whitespace[pipeline[0][0]]) {
      pipeline = ({});
      return 1;
    }
    return 0;
  }

  //! Clear the current state.
  void flush() {
    pstack->reset();
    pipeline = ({});
    ready = ({});
    last = 0;
    block = 0;
  }

  //! Show the current parser state. Used by "dump state".
  void show_state() {
    write("Current parser state\n");
    write("Parenthesis stack: %s\n", pstack->arr[..pstack->ptr]*" ");
    write("Current pipline: %O\n", pipeline);
    write("Last token: %O\n", last);
    write("Current block: %O\n", block);
  }

  string _sprintf(int type) {
    if(type=='O' || type=='t') return "HilfeParserState";
  }
}

//! In every Hilfe object (@[Evaluator]) there is a HilfeHistory
//! object that manages the result history. That history object is
//! accessible both from __ and ___Hilfe->history in Hilfe expressions.
private class HilfeHistory {

  private int size=10;
  private int last_entry_num;
  private array history = ({});

  //! Returns the absolute sequence number of the last
  //! result inserted into the history.
  int get_last_entry_num() {
    return last_entry_num;
  }

  //! Returns the absolute sequence number of the
  //! oldest result still in the history.
  int get_first_entry_num() {
    return last_entry_num - sizeof(history) +1;
  }

  //! Returns the maximum number of entries that can be
  //! stored in the history simultaneous.
  int get_maxsize() { return size; }

  //! Set the maximume number of entries that can be
  //! stored in the history simultaneous.
  void set_maxsize(int _size) {
    size = _size;
    if(sizeof(history)>size)
      history = history[sizeof(history)-size..];
  }

  //! Returns true if there is any items in the history.
  int has_content() { return sizeof(history); }

  //! Empty the history.
  void flush() {
    last_entry_num = 0;
    history = ({});
  }

  //! Add a result to the history.
  void add(mixed value) {
    last_entry_num++;
    history += ({ value });
    if(sizeof(history) == size+1)
      history = history[1..];
  }

  //! Get a value from the history as if it was an array, e.g.
  //! both positive and negative numbers may be used.
  mixed `[](int i) {
    if(i<0) {
      if(i<-sizeof(history))
	error("Hilfe History Error: Only %d entries in history.\n",
	      sizeof(history));
      return history[i];
    }
    if(i>last_entry_num)
      error("Hilfe History Error: Only %d entrues in history.\n",
	    sizeof(history));
    if(i-get_first_entry_num() < 0)
      error("Hilfe History Error: The oldest history entry is %d.\n",
	    get_first_entry_num());
    return history[i-get_first_entry_num()];

  }

  //! Shows the contents of the history.
  void show_history() {
    int abs_num = get_first_entry_num();
    int rel_num = -sizeof(history);
    foreach(history, mixed value)
      write(" %2d (%2d) : %s\n", abs_num++, rel_num++,
	    replace(sprintf("%O",value), "\n", "\n           "));
  }

  string _sprintf(int type) {
    if(type=='O' || type=='t') return "HilfeHistory";
  }
}


//
// The actual Hilfe
//

//! This class implements the actual Hilfe interpreter. It is accessible
//! as ___Hilfe from Hilfe expressions.
class Evaluator {

  //! This mapping contains the available Hilfe commands, including the
  //! built in ones (dump, exit, help, new, quit), so it is possible to
  //! replace or remove them.
  //!
  //! A command is a function or an object with `() defined. The command
  //! can be called in three different ways:
  //! @ul
  //!   @item
  //!      (Evaluator e, string command_line, array(string) tokens)
  //!      when commands are executed
  //!   @item
  //!      (0) when simple help is wanted
  //!   @item
  //!      (1) when extended help is wanted
  //! @endul
  //!
  //! It is recommended that command names are less then 11 characters
  //! long, that simple help is less than 54 characters long and that
  //! the extended help is less than 68 characters per line (to keep
  //! all presentation things like help etc look nice).
  mapping(string:function|object) commands = ([]);

  //! Keeps the state, e.g. multiline input in process etc.
  ParserState state = ParserState();

  //! The locally defined variables (name:value).
  mapping(string:mixed) variables;

  //! The types of the locally defined variables (name:type).
  mapping(string:string) types;

  //! The locally defined constants (name:value).
  mapping(string:mixed) constants;

  //! The locally defined functions (name:value).
  mapping(string:function) functions;

  //! The locally defined programs (name:value).
  mapping(string:program) programs;

  //! The current imports.
  array(string) imports;

  //! The current inherits.
  array(string) inherits;

  //! The current result history.
  HilfeHistory history = HilfeHistory();

  //! The function to use when writing this to the user.
  function write;

  //!
  void create()
  {
    print_version();
    commands->exit = command_exit;
    commands->quit = command_exit;
    commands->help = command_help;
    commands->dump = command_dump;
    commands->new = command_new;
    commands->hej = lambda() { write("Tjabba!\n"); };
    commands->look = lambda() {
		       write("You are inside a Hilfe. You see ");
		       if(!sizeof(variables+constants+functions+programs))
			 write("nothing.");
		       else
			 command_dump(this_object(), "dump");
		       write("\nYou can go in any direction from here.\n"); };
    reset_evaluator();
    add_constant("___Hilfe", this_object());
  }

  //! Displays the current version of Hilfe.
  void print_version()
  {
    write(version()+
	  " running Hilfe v3.0 (Incremental Pike Frontend)\n");
  }

  //! Cleras the current state, history and removes all locally
  //! defied variables, constants, functions and programs. Removes
  //! all imports and inherits. It does not reset the command mapping
  //! nor reevaluate the .hilferc file.
  void reset_evaluator() {
    state->flush();
    history->flush();
    variables = ([]);
    types = ([]);
    constants = ([]);
    functions = ([]);
    programs = ([]);
    imports = ({});
    inherits = ({});
  }

  //! Input a line of text into Hilfe. It checks if @[s] is
  //! ".", in which case it calls state->flush(). Otherwise
  //! just calls add_buffer.
  void add_input_line(string s)
  {
    if(s==".")
    {
      state->flush();
      return;
    }

    add_buffer(s);
  }

  //! Add buffer tokanizes the input string and determines if the
  //! new line is a Hilfe command. If not, it updates the current
  //! state with the new tokens and sends any and all complete
  //! expressions to evaluation in @[parse_expression].
  void add_buffer(string s)
  {
    // Tokanize the input
    array tokens;
    if(catch( tokens = Parser.Pike.split(s) )) {
      write("Hilfe Error: Could not tokanize input string.\n");
      return;
    }

    // See if first token is a command and not a defined entity.
    if(commands[tokens[0]] && zero_type(constants[tokens[0]]) &&
       zero_type(variables[tokens[0]]) && zero_type(functions[tokens[0]]) &&
       (sizeof(tokens)==1 || tokens[1]!=";")) {
      commands[tokens[0]](this_object(), s, tokens);
      return;
    }

    // See if the command is executed in overridden mode.
    if(sizeof(tokens)>1 && tokens[0]=="." && commands[tokens[1]]) {
      commands[tokens[1]](this_object(), s, tokens);
      return;
    }

    // Push new tokens into our state.
    string err = catch( state->feed(tokens) );
    if(err) {
      if(stringp(err))
	write("Hilfe Error: %s\n", err);
      else
	write(describe_backtrace(err));
      state->flush();
    }

    // See if any complete expressions came out on the other side.
    if(state->datap())
      foreach(state->read(), array(string) tokens) {
	string|int ret = parse_expression(tokens);
	if(ret) write(ret);
      }
  }


  //
  //
  // Parser code
  //
  //

  private array(string) remove_whitespace_tokens(array(string) tokens) {
    array(string) ret = ({});
    foreach(tokens, string token) {
      if(whitespace[token[0]]) continue;
      ret += ({ token });
    }
    return ret;
  }

  private void add_hilfe_constant(array(string) tokens) {
    if(object o=hilfe_compile("constant " + tokens_to_code(tokens) + ";\nmixed ___HilfeWrapper() { return " +
		     tokens[0] + "; }\n", tokens[0])) {
      constants[tokens[0]] = o->___HilfeWrapper();
    }
  }

  private void add_hilfe_variable(string type, array(string) tokens) {
    int(0..1) existed;
    mixed old_value;
    if(!zero_type(variables[tokens[0]])) {
      old_value = m_delete(variables, tokens[0]);
      existed = 1;
    }
    if(object o=hilfe_compile(type + " " + tokens_to_code(tokens) + ";\nmixed ___HilfeWrapper() { return " +
			      tokens[0] + "; }\n", tokens[0])) {
      variables[tokens[0]] = o->___HilfeWrapper();
      types[tokens[0]] = type;
    }
    else if(existed)
      variables[tokens[0]] = old_value;
  }

  private void add_hilfe_entity(string type, array(string) tokens, mapping vtype) {
    int(0..1) existed;
    mixed old_value;
    if(vtype[tokens[0]]) {
      old_value = m_delete(vtype, tokens[0]);
      existed = 1;
    }

    if(object o=hilfe_compile(type + " " + tokens_to_code(tokens) + ";\nmixed ___HilfeWrapper() { return " +
			      tokens[0] + "; }\n", tokens[0])) {
      vtype[tokens[0]] = o->___HilfeWrapper();
    }
    else if(existed)
      vtype[tokens[0]] = old_value;
  }

  //! Parses a Pike expression. Returns 0 if everything went well,
  //! or a string with an error message otherwise.
  int(0..0)|string parse_expression(array(string) tokens)
  {
    string code = tokens*"";
    tokens = remove_whitespace_tokens(tokens);

    if(tokens[0]==";") return 0;

    // Identify the type of statement so that we can intercept
    // variable declarations and store them locally.
    foreach(tokens, string token)
      if(modifier[token])
	return "Hilfe Error: Modifier \"" + token +
	  "\" not allowed on top level in Hilfe.\n";
      else
	break;

    string type = tokens[0];
    if(tokens[1]==".") type=".object";
    if(programs[tokens[0]] && tokens[1]!="(") type=".local";

    switch(type)
    {
      case "if":
      case "for":
      case "do":
      case "while":
      case "foreach":
	// Parse loops.
	evaluate("mixed ___HilfeWrapper() { " + code + " ; }\n",0);
	return 0;

      case "inherit":
      {
	inherits += ({ tokens_to_code(tokens[1..sizeof(tokens)-2]) });
	if(!hilfe_compile(""))
	  inherits = inherits[..sizeof(inherits)-2];
	return 0;
      }

      case "import":
      {
	imports += ({ tokens_to_code(tokens[1..sizeof(tokens)-2]) });
	if(!hilfe_compile(""))
	  imports = imports[..sizeof(imports)-2];
	return 0;
      }

      case "constant":
      {
	int pos = 1;

	while(pos<sizeof(tokens)) {
	  array def = ({});
	  int plevel;
	  while((tokens[pos]!="," && tokens[pos]!=";") || plevel) {
	    if(tokens[pos]=="(") plevel++;
	    if(tokens[pos]==")") plevel--;
	    def += ({ tokens[pos++] });
	    if(pos==sizeof(tokens))
	      return "Hilfe Error: Bug in constant handling. Please report this!\n";
	  }
	  pos++;
	  add_hilfe_constant(def);
	}

	return 0;
      }

      case "class":
	add_hilfe_entity(tokens[0], tokens[1..], programs);
	return 0;

      case "int":
      case "void":
      case "object":
      case ".object":
      case ".local":
      case "array":
      case "mapping":
      case "string":
      case "multiset":
      case "float":
      case "mixed":
      case "program":
      case "function":
      {
	// This is either a variable declaration or a new function.

	string type = tokens[0];
	int pos=1;

	// Find out the whole type, e.g. Stdio.File|mapping(string:int(0..3))
	while(tokens[pos]=="." || tokens[pos]=="|" || tokens[pos]=="(") {
	  if(tokens[pos]=="." || tokens[pos]=="|")
	    type += tokens[pos++] + tokens[pos++];
	  else {
	    int plevel=0;
	    do {
	      type += tokens[pos];
	      if(tokens[pos]==",") type += " ";
	      if(tokens[pos]=="(") plevel++;
	      if(tokens[pos]==")") plevel--;
	      pos++;
	    } while(plevel);
	  }
	}

	if(tokens[pos]==";" || tokens[pos]=="->" || tokens[pos]=="[")
	  break;

	// This is a new function
	if(tokens[pos+1]=="(") {
	  if(constants[tokens[pos]])
	    return "Hilfe Error: \"" + tokens[pos] + "\" already defined as constant.\n";
	  add_hilfe_entity(type, tokens[pos..], functions);
	  return 0;
	}

	while(pos<sizeof(tokens)) {
	  array def = ({});
	  int plevel;
	  while((tokens[pos]!="," && tokens[pos]!=";") || plevel) {
	    if(tokens[pos]=="(") plevel++;
	    if(tokens[pos]==")") plevel--;
	    def += ({ tokens[pos++] });
	    if(pos==sizeof(tokens))
	      return "Hilfe Error: Bug in variable handeling. Please report this!\n";
	  }
	  pos++;
	  add_hilfe_variable(type, def);
	}

	return 0;
      }
    }

    // parse expressions
    evaluate("mixed ___HilfeWrapper() { return " + code + " }\n", 1);
    return 0;
  }


  //
  //
  // Compilation/Evaluation code
  //
  //

  //! The last created wrapper in which an expression was evaluated.
  string last_compiled_expr;

  private object compile_handler = class
    {
      void compile_error(string file,int line,string err)
      {
	write(sprintf("Compiler Error: %s:%s:%s\n",master()->trim_file_name(file),
		      line?(string)line:"-", err));
      }

      string _sprintf(int type) {
	if(type=='O' || type=='t') return "HilfeCompileHandler";
      }
    }();

  // We need this as long as "( < > )" isn't valid Pike code.
  private string tokens_to_code(array(string) tokens) {
    string ret = "";
    foreach(tokens, string token) {
      ret += token;
      if( !(< "(", ">" >)[token] ) ret += " ";
    }
    return ret;
  }

  //! Creates a wrapper and compiles the pike code @[f] in it.
  //! If a new variable is compiled to be tested, it's name
  //! should be given in @[new_var] so that magically defined
  //! entities can be undefined and a warning printed.
  object hilfe_compile(string f, void|string new_var)
  {
    if(new_var && commands[new_var])
      write("Hilfe Warning: Command %O no longer reachable. Use %O instead.\n",
	    new_var, "."+new_var);

    if(new_var=="___hilfe" || new_var=="___Hilfe" || new_var=="___HilfeWrapper" ) {
      write("Hilfe Error: Symbol %O must not be defined.\n"
	    "             It is used internally by Hilfe.\n", new_var);
      return 0;
    }

    mapping symbols = constants + functions + programs;

    if(new_var=="__")
      write("Hilfe Warning: History variable __ is no longer reachable.\n");
    else if(zero_type(symbols["__"]) && zero_type(variables["__"])) {
      symbols["__"] = history;
    }

    if(new_var=="_")
      write("Hilfe Warning: History variable _ is no longer reachable.\n");
    else if(zero_type(symbols["_"]) && zero_type(variables["__"])
	    && history->has_content()) {
      symbols["_"] = history[-1];
    }

    string prog =
      ("#pragma unpragma_strict_types\n" +

       map(inherits, lambda(string f) { return "inherit "+f+";\n"; }) * "\n" + "\n" +

       map(imports, lambda(string f) { return "import "+f+";\n"; }) * "\n" + "\n" +

       map(indices(symbols),
	   lambda(string f) {
	     return sprintf("constant %s=___hilfe.%s;", f, f);
	   } ) * "\n" + "\n" +

       map(indices(variables),
	   lambda(string f) {
	     return sprintf("%s %s=___hilfe.%s;", types[f], f, f);
	   }) * "\n" + "\n" +

       "\nmapping query_variables() { return ([\n"+
       map(indices(variables),
	   lambda(string f) {
	     return sprintf("    \"%s\":%s,",f,f);
	   }) * "\n" +
       "\n  ]);\n}\n"+

       "# 1\n" + f + "\n");

    last_compiled_expr = prog;
    program p;
    mixed err;

    mixed oldwrite=all_constants()->write;
    add_constant("write", write);
    add_constant("___hilfe", symbols+variables);
    err=catch( p=compile_string(prog, "-", compile_handler) );
    add_constant("___hilfe");
    add_constant("write", oldwrite);

    if(err)
    {
      //      write(describe_backtrace(err));
      //      write("Hilfe Error: Couldn't compile expression.\n");
      return 0;
    }

    object o;
    if(err=catch(o=clone(p)))
    {
      trace(0);
      write(describe_backtrace(err));
      return 0;
    }

    return o;
  }

  //! Compiles the Pike code @[a] and evaluate it by
  //! calling ___HilfeWrapper in the generated object.
  //! If @[show_result] is set the result will be displayed
  //! and the result buffer updated with its value.
  void evaluate(string a, int(0..1) show_result)
  {
    object o;
    if( o=hilfe_compile(a) )
    {
      mixed err;
      mixed res;
      if( (err=catch(res=o->___HilfeWrapper())) || (err=catch(a=sprintf("%O", res))) )
      {
	trace(0);
	if(objectp(err) && err->is_generic_error)
	  catch { err = ({ err[0], err[1] }); };

	if(arrayp(err) && sizeof(err)==2 && arrayp(err[1]))
	{
	  err[1]=err[1][sizeof(backtrace())..];
	  write(describe_backtrace(err));
	}
	else
	  write("Hilfe Error: Error in evaluation: %O\n",err);
      }
      else {
	if(show_result) {
	  history->add(res);
	  write( "Result %d: %s\n", history->get_last_entry_num(),
		 replace(a, "\n", "\n        ") );
	}
	else
	  write("Ok.\n");

	// Import variable changes from object.
	variables=o->query_variables();
      }
    }
  }

  string _sprintf(int type) {
    if(type=='O' || type=='t') return "HilfeEvaluator";
  }
}

//! This is a wrapper containing a user interface to the Hilfe @[Evaluator]
//! so that it can actually be used. This wrapper uses the @[Stdio.Readline]
//! module to interface with the user. All input history is handled by
//! that module, and as a consequence loading and saving .hilfe_history is
//! handled in this class. Also .hilferc is handled by this class.
class StdinHilfe
{
  inherit Evaluator;

  //! The readline object,
  Stdio.Readline readline;

  private int(0..1) unsaved_history;

  void destroy() {
    //    readline->get_history()->pop();
    save_history();
  }

  //! Saves the user input history, if possible, when called.
  void save_history()
  {
    if(!unsaved_history) return;
    unsaved_history = 0;
    catch {
      if(string home=getenv("HOME")||getenv("USERPROFILE"))
      {
	rm(home+"/.hilfe_history~");
	if(object f=Stdio.File(home+"/.hilfe_history~","wct"))
	{
	  f->write(readline->get_history()->encode());
	  f->close();
	}
	rm(home+"/.hilfe_history");
	mv(home+"/.hilfe_history~",home+"/.hilfe_history");
#if constant(chmod)
	chmod(home+"/.hilfe_history", 0600);
#endif
      }
    };
  }

  void signal_trap(int s)
  {
    save_history();
    exit(1);
  }

  //!
  void create()
  {
    write=predef::write;
    ::create();

    if(string home=getenv("HOME")||getenv("USERPROFILE"))
    {
      if(string s=Stdio.read_file(home+"/.hilferc"))
	add_buffer(s);
    }

    readline = Stdio.Readline();
    array(string) hist;
    catch{
      if(string home=getenv("HOME")||getenv("USERPROFILE"))
      {
	if(Stdio.File f=Stdio.File(home+"/.hilfe_history","r"))
	{
	  string s=f->read()||"";
	  hist=s/"\n";
	  readline->enable_history(hist);
	}
      }
    };
    if(!hist)
      readline->enable_history(512);
    signal(signum("SIGINT"),signal_trap);

    for(;;)
    {
      readline->set_prompt(state->finishedp() ? "> " : ">> ");
      string s=readline->read();

      if(!s)
	break;

      unsaved_history = 1;
      add_input_line(s);
    }
    save_history();
    destruct(readline);
    write("Terminal closed.\n");
  }
}

//!
class GenericHilfe
{
  inherit Evaluator;

  //!
  void create(Stdio.FILE in, Stdio.File out)
  {
    write=out->write;
    ::create();

    while(1)
    {
      write(state->finishedp() ? "> " : ">> ");
      if(string s=in->gets())
	add_input_line(s);
      else {
	write("Terminal closed.\n");
	return;
      }
    }
  }
}

//!
class GenericAsyncHilfe
{
  inherit Evaluator;
  Stdio.File infile, outfile;

  string outbuffer="";

  void write_callback()
  {
    int i=outfile->write(outbuffer);
    outbuffer=outbuffer[i..];
  }

  void send_output(string s, mixed ... args)
  {
    outbuffer+=sprintf(s,@args);
    write_callback();
  }

  string inbuffer="";
  void read_callback(mixed id, string s)
  {
    inbuffer+=s;
    foreach(inbuffer/"\n",string s)
      {
	add_input_line(s);
	write(state->finishedp() ? "> " : ">> ");
      }
  }

  void close_callback()
  {
    write("Terminal closed.\n");
    destruct(this_object());
    destruct(infile);
    if(outfile) destruct(outfile);
  }

  //!
  void create(Stdio.File in, Stdio.File out)
  {
    infile=in;
    outfile=out;
    in->set_nonblocking(read_callback, 0, close_callback);
    out->set_write_callback(write_callback);

    write=send_output;
    ::create();
    write(state->finishedp() ? "> " : ">> ");
  }
}

int main() {
  StdinHilfe();
  return 0;
}
