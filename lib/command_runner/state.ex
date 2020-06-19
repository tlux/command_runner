defmodule CommandRunner.State do
  @moduledoc false

  defstruct refs: %{}, ports: %{}

  @type ref_entry :: %{client: GenServer.from(), port: port}

  @type port_entry :: %{
          client: GenServer.from(),
          ref: reference,
          result:
            {term, (term, Collectable.command() -> Collectable.t() | term)}
        }

  @type t :: %__MODULE__{
          refs: %{optional(reference) => ref_entry},
          ports: %{optional(port) => port_entry}
        }

  @spec entry_exists?(t, reference) :: boolean
  def entry_exists?(%__MODULE__{} = state, ref) do
    Map.has_key?(state.refs, ref)
  end

  @spec put_entry(t, reference, port, GenServer.from()) :: t
  def put_entry(%__MODULE__{} = state, ref, port, client) do
    %{
      state
      | refs: Map.put(state.refs, ref, %{client: client, port: port}),
        ports:
          Map.put(state.ports, port, %{
            client: client,
            ref: ref,
            result: Collectable.into("")
          })
    }
  end

  @spec fetch_entry_by_ref(t, reference) :: {:ok, ref_entry} | :error
  def fetch_entry_by_ref(%__MODULE__{} = state, ref) do
    Map.fetch(state.refs, ref)
  end

  @spec fetch_entry_by_port(t, port) :: {:ok, port_entry} | :error
  def fetch_entry_by_port(%__MODULE__{} = state, port) do
    Map.fetch(state.ports, port)
  end

  @spec delete_entry(t, reference, port) :: t
  def delete_entry(%__MODULE__{} = state, ref, port) do
    %{
      state
      | refs: Map.delete(state.refs, ref),
        ports: Map.delete(state.ports, port)
    }
  end

  @spec put_result(t, port, {term, function}) :: t
  def put_result(%__MODULE__{} = state, port, result) do
    %{state | ports: put_in(state.ports, [port, :result], result)}
  end
end
