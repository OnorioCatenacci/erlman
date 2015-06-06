defmodule Erlman do

  require ErlmanNroff

  def manpath do
    start = to_string(:os.find_executable('erl'))
    finish = Path.split(start) |>
             Stream.scan(&Path.join(&2,&1)) |> 
             Enum.filter( fn(p)  -> File.exists?(Path.join([p,"man","man3","ets.3"])) end ) |>
             List.last
    Path.join(finish,"man")
  end

  @doc """
  Expects the Elixir version of the erlang function or module name
  and returns the path to it's man page.

  ## Example

        iex> {:ok,path} = Erlman.manpage(":crypto.hash")
        {:ok, "/usr/local/Cellar/erlang/17.5/lib/erlang/man/man3/crypto.3" }

  """
  def manpage(elixir_erlang_ref) do
    target = convert(elixir_erlang_ref) |> Enum.at(0)
    manfile = mandirs(Erlman.manpath) |>
              Enum.find_value(fn(dir) -> has_man?(dir,target) end)
    case manfile do
      nil -> {:error, :enoent}
       _  -> {:ok, manfile}
    end
  end

  def manstring(function_name) do 
    case manpage(function_name) do
      {:ok, manfile} -> File.read!(manfile)
      {:error, :enoent} -> :nofile
    end
  end

  def module_doc(elixir_erlang_ref) do
    doc = manstring(elixir_erlang_ref)
    Nroff.to_markdown(doc)
  end

  def function_doc(elixir_erlang_ref) do
    function = convert(elixir_erlang_ref) |> Enum.at(1)
    doc = manstring(elixir_erlang_ref)
    fdoc = Nroff.find(doc,function)
    Nroff.to_markdown(fdoc)
  end 

  @doc """ 
  Emulate behaviour of Code.gets_docs as far as possible.

  Returns the docs for the given module.
  The return value depends on the kind value:

  :docs - list of all docstrings attached to functions and macros using the @doc attribute
  :moduledoc - tuple {<line>, <doc>} where line is the line on which module definition starts and doc is the string attached to the module using the @moduledoc attribute
  :all - a keyword list with both :docs and :moduledoc

  """
  def get_docs(module,kind) do
    mandoc = Erlman.manstring(module)
    if mandoc == :nofile do
      nil
    else 
     funcs = function_exports(module)
     parse_docs(module,funcs,mandoc,kind)
    end
  end

  def parse_docs(module,funcs,mandoc,kind ) do
    [nroff_mod,nroff_func] = ErlmanNroff.split(mandoc)
    case kind do 
      :docs      -> get_function_docs(module,funcs,nroff_func)
      :moduledoc -> get_moduledoc(module,nroff_mod)
      :all       -> get_all_docs(module,funcs,mandoc)
      _          -> nil
    end
  end 

  @doc """
  Return the results of :module.module_info(:exports)
  Will raise error if :module is not loaded. 
  """
  def function_exports(module) do
    code = module<>".module_info(:exports)"
    Code.eval_string(code,[],__ENV__) |> elem(0)
  end 

  @doc """
    Return a list of tuples of the form 
    {{_function, _arity}, _line, _kind, _signature, text} 
  """
  def get_function_docs(module,funcs,nroff_func) do
    ErlmanNroff.list_functions(nroff_func) |>
    Enum.filter_map(fn(d_str) -> ErlmanNroff.match_function(d_str,funcs) end , 
                    fn(d_str) -> ErlmanNroff.parse_function(d_str,funcs) end )
  end

  def get_moduledoc(module,mandoc) do
    {1,ErlmanNroff.to_markdown(mandoc)}
  end 

  def get_all_docs(module,mandocs,funcs) do
    true
  end 

  # There needs to be a whole lot of clean up wrt whether module is an atom or string. 
  def h(elixir_erlang_ref) do
    search = convert(elixir_erlang_ref)
    case Enum.count(search) do
      1 -> print_doc(elixir_erlang_ref, elem(get_docs(elixir_erlang_ref, :moduledoc), 1) )
      2 -> find_andprint_fdoc(search, get_docs(":"<>List.first(search), :docs) )
    end
  end 

  def find_andprint_fdoc(search, doc_list ) do
    [module,fname] = search
    fatom = String.to_atom(fname)
    arity = find_arity(module,fname)
    arity |> Enum.map(fn(a) -> print_func(doc_list,search,a) end )
  end 

  def print_func(doc_list, search, arity) do
    [module, fname] = search
    doc_tup = List.keyfind(doc_list, { String.to_atom(fname), arity }, 0 )
    { _tup, _line, _kind, _sig, info } = doc_tup
    print_doc("def :#{module}.#{fname}",info)
  end 

  def find_arity(module,fname) do
    function_exports(":"<>module) |>
    Enum.filter_map(fn(tup) -> elem(tup,0) == String.to_atom(fname) end, 
                    fn(tup) -> elem(tup,1) end )
  end

  defp print_doc(heading, doc) do
    doc = doc || ""
    if opts = IEx.Config.ansi_docs do
      IO.ANSI.Docs.print_heading(heading, opts)
      IO.ANSI.Docs.print(doc, opts)
    else
      IO.puts "* #{heading}\n"
      IO.puts doc
    end
  end

  defp mandirs(path) do
    File.ls!(path) |> 
    Enum.filter_map(fn(entry) -> Regex.match?(~r/^man[1-8]/, entry) end , fn(entry) -> Path.join(path,entry) end ) |>
    Enum.filter(fn(entry) -> File.dir?(entry) end)
  end

  def convert(elixir_erlang_ref) do 
    String.lstrip(elixir_erlang_ref, ?: ) |>
    String.split(".")
  end

  defp has_man?(dir,target) do
    manfile = page(dir,target)
    case File.exists?(manfile) do
      true -> manfile
      _    -> false
    end
  end 

  defp page(dir,target) do
    section = target<>"."<>String.last(dir)
    Path.join(dir,section)
  end 
  
end
