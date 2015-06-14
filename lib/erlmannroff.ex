defmodule ErlmanNroff do
  @moduledoc """
  This module is meant to parse just enough nroff to convert the erlang man pages
  to markdown format compatible with Code.get_docs in elixir. It relies heavily 
  on the fact that Erlang man pages have a standard conversion from the original
  XML version of the documentation. 
  """
	@man_macros ~W(.TH .SH .SS .TP .LP .RS .RE .nf .fi .br .B )

  @doc """
  Split string into list of function strings. 
  We assume erlang nroff that has this format. 

      .B
      function(arg1, arg2) -> ResultType
  """
	def list_functions(string) do
    String.split(string,"\n.B\n") 
	end 

  @doc """
  Splits manpage string into Module and Function Parts. 
  """
  def split(manstring) do
    String.split(manstring,".SH EXPORTS", parts: 2)
  end

  @doc """
  Parse a function string.
  foo(arg,arg,arg) -> ResultType
  functions should be the result of :module.module_info(:exports)
  Return should look like 
   {{_function, _arity}, _line, _kind, _signature, text} 
   signature is a list of tuples of the form {:arg,[],nil}
  """
  def parse_function(nroff_docstring,functions) do
    fkey = match_function(nroff_docstring,functions)
    arity = get_arity(nroff_docstring, functions)
    signature = get_signature(arity)
    {{fkey, arity}, 1, :def, signature, to_markdown(nroff_docstring) }
  end

  def match_function(nroff_dstring, functions) do 
    found = Dict.keys(functions) |> 
            Enum.map(fn(x) -> Atom.to_string(x) end ) |> 
            Enum.find(fn(fname) -> String.starts_with?(nroff_dstring,fname) end )
    case found do 
      nil -> nil
      _   -> String.to_atom(found)
    end 
  end 

  @doc """
  Find first \(, count the number of commas until the \)
  """
  def get_arity(nroff_docstring,functions) do
    String.codepoints(nroff_docstring) |>
    Stream.transform(0,fn(x,acc) -> 
                      case x do 
                        "("  -> {[0], acc }  
                        ","  -> {[0], acc }
                        ")"  -> {:halt, acc} 
                        _    -> {[], acc}
                      end 
                     end ) |>
    Enum.count 
  end 

  def get_signature(arity) do
    0..arity |> Enum.map(fn(x) -> { "arg"<>Integer.to_string(x) , [], nil } end )
  end 
	
  # This is serious cheating, we should really implement the nroff state machine. 
  # But since that is mostly about indentation, see how far we can get. 
  def to_markdown(string) do
    String.split(string, "\n") |>
    Enum.map_reduce("", fn(line,prepend) -> translate(line,prepend) end) 
  end

  # Return { line, prepend }
  def translate(line, prepend) do
    case String.starts_with?(line, @man_macros) do
      true  -> { swap_macro(line)
      false -> { swap_inline(line), "" }
    end 
  end

	def swap_inline(line) do 
		newline = String.replace(line,"\\fI","`") |> 
              String.replace("\\fB","`") |> 
		          String.replace("\\fR","`") |>
		          String.replace("\\&","") 
    newline<>"\n"
	end
  

	def get_macro(line) do
		[ macro | line ] = String.split(line,~r/\s/, parts: 2 )
		case line do 
			[] -> {macro, "" }
      _  -> {macro, Enum.at(line,0)}
    end 
	end 

  @doc """
  Attempt to emulate the nroff state machine as much as possible by 
  returning both the line and a prepend expression for the next line. 
  """
	def swap_macro(line) do
		{ macro, line } = get_macro(line)
		swap_macro(macro,line)
	end 

	def swap_macro(".TH", line) do
		{ "# "<>line<>"\n", "" }
	end

	def swap_macro(".SH", line) do
		{ "## "<>line<>"\n", "" }
	end

  def swap_macro(".SS", line) do
    { "### "<>line<>"\n", "" }
  end

  def swap_macro(".TP", line) do
    { line , "" } 
  end

  def swap_macro(".LP", line) do
    { line , "" } 
  end

  @doc """
    Indent count.to_i spaces, in general this is not 
    translatable to markdown w/o context ( i.e. is list?)
  """
  def swap_macro(".RS", count) do
    { "", "" } 
  end

  def swap_macro(".RE", line) do
    { "", "" }  
  end

  @doc """
    Turn off text fill, largely used to translate <code> blocks
  """
  def swap_macro(".nf", line) do
   { line , "    " }
  end

	def swap_macro(".fi", line) do
   { line, "" } 
  end

  @doc """
  This should never be called since we split on .B to find functions.
  """
  def swap_macro(".B", line) do
    { line , "" } 
  end
 
  def swap_macro(".br", line) do
   { "\n"<>line , "" }  
  end

end