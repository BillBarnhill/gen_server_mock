%%%-------------------------------------------------------------------
%%% File    : gen_server_mock.erl
%%% Author  : nmurray@attinteractive.com
%%% Description : Mocking for gen_server. Expectations are ordered, every
%%%    message required and no messages more than are expected are allowed.
%%%
%%% Expectations get the same input as the handle_(whatever) gen_server methods. They should return -> ok | {ok, NewState}
%%% Created     : 2009-08-05
%%% Modified 2012-11-30 by Bill Barnhill <=bill.barnhill> to:
%%%     .. Use inline eunit tests, as part of rebar-ification
%%%     .. Cleaned up error output, added param to expect calls so that function form is displayed
%%% Inspired by: http://erlang.org/pipermail/erlang-questions/2008-April/034140.html
%%%-------------------------------------------------------------------

-module(gen_server_mock).
-behaviour(gen_server).

% API
-export([new/0, new/1, stop/1, crash/1,
        expect/4, expect_call/3, expect_info/3, expect_cast/3,
        assert_expectations/1]).

% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% Macros
-define(SERVER, ?MODULE).
-define(DEFAULT_CONFIG, {}).

-record(state, {
        expectations
}).

-record(expectation, {
        type,
        lambda,
        lambda_data
}).

-ifndef(TEST).

% steal assert from eunit
-define(assert(BoolExpr),
    ((fun () ->
        case (BoolExpr) of
        true -> ok;
        __V -> .erlang:error({assertion_failed,
                      [{module, ?MODULE},
                       {line, ?LINE},
                       {expression, (??BoolExpr)},
                       {expected, true},
                       {value, case __V of false -> __V;
                           _ -> {not_a_boolean,__V}
                           end}]})
        end
      end)())).

-endif.

-define(raise(ErrorName),
    erlang:error({ErrorName,
                  [{module, ?MODULE},
                      {line, ?LINE}]})).

-define(raise_info(ErrorName, Info),
    erlang:error({ErrorName,
                  [{module, ?MODULE},
                      {line, ?LINE},
                      {info, Info}
                  ]})).


-define (DEBUG, true).
-define (TRACE(X, M), case ?DEBUG of
  true -> io:format(user, "TRACE ~p:~p ~p ~p~n", [?MODULE, ?LINE, X, M]);
  false -> ok
end).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start() -> {ok,Pid} | ignore | {error,Error}
%% Description: Alias for start_link
%%--------------------------------------------------------------------
start() ->
    start_link([]). 

%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(Config) ->
    gen_server:start_link(?MODULE, [Config], []). % start a nameless server

%%--------------------------------------------------------------------
%% Function: new() -> {ok, Mock} | {error, Error}
%% Description: 
%%--------------------------------------------------------------------
new() ->
    case start() of
        {ok, Pid} ->
            {ok, Pid};
        {error, Error} ->
            {error, Error};
        Other ->
            {error, Other}
    end.

%%--------------------------------------------------------------------
%% Function: new(N) when is_integer(N) -> [Pids]
%% Description: Return multiple Mock gen_servers
%%--------------------------------------------------------------------
new(N) when is_integer(N) -> % list() of Pids
    lists:map(fun(_) -> {ok, Mock} = new(), Mock end, lists:seq(1, N)).

%%--------------------------------------------------------------------
%% Function: expect(Mock, Type, Callback) -> ok
%% Types: Mock = pid()
%%        Type = atom() = call | cast | info 
%%        Callback = fun(Args) -> ok | {ok, NewState} | {ok, ResponseValue, NewState}
%%          Args matches signature of handle_* in gen_server. e.g. handle_call
%% 
%% Description: Set an expectation of Type
%%--------------------------------------------------------------------
expect(Mock, Type, Callback, CallbackMeta) ->
    Exp = #expectation{type=Type, lambda=Callback, lambda_data=CallbackMeta},
    added = gen_server:call(Mock, {expect, Exp}),
    ok.

%%--------------------------------------------------------------------
%% Function: expect_call(Mock, Callback) -> ok
%% Types: Mock = pid()
%%        Callback = fun(Args) -> ok | {ok, NewState} | {ok, ResponseValue, NewState}
%%          Args matches signature of handle_call in gen_server.
%% 
%% Description: Set a call expectation
%%--------------------------------------------------------------------
expect_call(Mock, Callback, CallbackMeta) ->
    expect(Mock, call, Callback, CallbackMeta).

%%--------------------------------------------------------------------
%% Function: expect_info(Mock, Callback) -> ok
%% Types: Mock = pid()
%%        Callback = fun(Args) -> ok | {ok, NewState} | {ok, ResponseValue, NewState}
%%          Args matches signature of handle_info in gen_server.
%% 
%% Description: Set a info expectation
%%--------------------------------------------------------------------
expect_info(Mock, Callback, CallbackMeta) ->
    expect(Mock, info, Callback, CallbackMeta).

%%--------------------------------------------------------------------
%% Function: expect_cast(Mock, Callback) -> ok
%% Types: Mock = pid()
%%        Callback = fun(Args) -> ok | {ok, NewState} | {ok, ResponseValue, NewState}
%%          Args matches signature of handle_cast in gen_server.
%% 
%% Description: Set a cast expectation
%%--------------------------------------------------------------------
expect_cast(Mock, Callback, CallbackMeta) ->
    expect(Mock, cast, Callback, CallbackMeta).

%%--------------------------------------------------------------------
%% Function: assert_expectations(Mock)-> ok
%% Types: Mock = pid() | [Mocks]
%% Description: Ensure expectations were fully met
%%--------------------------------------------------------------------
assert_expectations(Mock) when is_pid(Mock) ->
    assert_expectations([Mock]);
assert_expectations([H|T]) ->
    case gen_server:call(H, assert_expectations) of
        {error, unmet_gen_server_expectation, ExpLeft} -> 
            erlang:error({unmet_expectations, ExpLeft});
        ok -> assert_expectations(T)
    end;
assert_expectations([]) ->
    ok.

        
%?raise_info(unmet_gen_server_expectation, ExpLeft);

%%--------------------------------------------------------------------
%% Function: stop(Mock)-> ok
%% Types: Mock = pid() | [Mocks]
%% Description: Stop the Mock gen_server normally
%%--------------------------------------------------------------------
stop(H) when is_pid(H) ->
    stop([H]);
stop([H|T]) ->
    gen_server:cast(H, {'$gen_server_mock', stop}),
    stop(T);
stop([]) ->
    ok.

crash(H) when is_pid(H) ->
    crash([H]);
crash([H|T]) ->
    gen_server:cast(H, {'$gen_server_mock', crash}),
    crash(T);
crash([]) ->
    ok.



%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------

init(_Args) -> 
    InitialState = #state{expectations=[]},
    {ok, InitialState}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------

% return the state
handle_call(state, _From, State) ->
    {reply, {ok, State}, State};

handle_call({expect, Expectation}, _From, State) ->
    {ok, NewState} = store_expectation(Expectation, State),
    {reply, added, NewState};

handle_call(assert_expectations, _From, State=#state{expectations=ExpLeft}) when length(ExpLeft) > 0 ->
    ExpData = lists:map(fun (#expectation{type=Type, lambda_data=FnData}) -> 
                                {Type, FnData} 
                        end, ExpLeft), 
    {reply, {error, unmet_gen_server_expectation, ExpData}, State};

handle_call(assert_expectations, _From, State) ->
    {reply, ok, State};

handle_call(Request, From, State) -> 
    {ok, Reply, NewState} = reply_with_next_expectation(call, Request, From, undef, undef, State),
    {reply, Reply, NewState}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast({'$gen_server_mock', stop}, State) -> 
    {stop, normal, State};
handle_cast({'$gen_server_mock', crash}, State) -> 
    {stop, crash, State};
handle_cast(Msg, State) -> 
    {ok, _Reply, NewState} = reply_with_next_expectation(cast, undef, undef, Msg, undef, State),
    {noreply, NewState}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info(Info, State) -> 
    {ok, _Reply, NewState} = reply_with_next_expectation(info, undef, undef, undef, Info, State),
    {noreply, NewState}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) -> 
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) -> 
    {ok, State}.

%%
%% private functions
%%
store_expectation(Expectation, State) -> % {ok, NewState}
    NewExpectations = [Expectation|State#state.expectations],  
    NewState = State#state{expectations = NewExpectations},
    {ok, NewState}.

pop(L) -> % {Result, NewList} | {undef, []}
    case L of
        [] -> {undef, []};
        List -> {lists:last(List), lists:sublist(List, 1, length(List) - 1)}
    end.

pop_expectation(State) -> % {ok, Expectation, NewState}
    {Expectation, RestExpectations} = case pop(State#state.expectations) of
        {undef, []} -> ?raise(no_gen_server_mock_expectation);
        {Head, Rest} -> {Head, Rest}
    end,
    NewState = State#state{expectations = RestExpectations},
    {ok, Expectation, NewState}.

reply_with_next_expectation(Type, Request, From, Msg, Info, State) -> % -> {ok, Reply, NewState}
    {ok, Expectation, NewState} = pop_expectation(State),
    ?assert(Type =:= Expectation#expectation.type), % todo, have a useful error message, "expected this got that" 

    {ok, Reply, NewState2} = try call_expectation_lambda(Expectation, Type, Request, From, Msg, Info, NewState) of
        {ok, R, State2} -> {ok, R, State2}
    catch
        error:function_clause ->
            ?raise_info(unexpected_request_made, {Expectation, Type, Request, From, Msg, Info, NewState})
    end,
    {ok, Reply, NewState2}.

% hmm what if we want better response. 
call_expectation_lambda(Expectation, Type, Request, From, Msg, Info, State) -> % {ok, NewState}
    L = Expectation#expectation.lambda,
    Response = case Type of 
       call -> L(Request, From, State);
       cast -> L(Msg, State);
       info -> L(Info, State);
          _ -> L(Request, From, Msg, Info, State)
    end,
    case Response of % hmmm
        ok                       -> {ok, ok,       State};
        {ok, NewState}           -> {ok, ok,       NewState};
        {ok, ResponseValue, NewState} -> {ok, ResponseValue, NewState};
        Other -> Other
    end.

%% =============================================================
%% Tests
%% =============================================================

-ifdef(TEST).

-define(exit_error_name(Exception),
    ((fun () ->
    {{{ErrorName, _Info }, _Trace }, _MoreInfo} = Exception,
    ErrorName
    end)())).


everything_working_normally_test_not_test() ->
    {ok, Mock} = gen_server_mock:new(),    
    gen_server_mock:expect(Mock, call, fun({foo, hi}, _From, _State) -> ok end, [{foo, hi}, '_', '_']),
    gen_server_mock:expect_call(Mock, fun({bar, bye}, _From, _State) -> ok end, [{bar, bye}, '_', '_']),

    ok = gen_server:call(Mock, {foo, hi}),  
    ok = gen_server:call(Mock, {bar, bye}),  

    ok = gen_server_mock:assert_expectations(Mock).



missing_expectations_test_not_test() ->
    {ok, Mock} = gen_server_mock:new(),
    gen_server_mock:expect(Mock, call, fun({foo, hi}, _From, _State) -> ok end, [{foo, hi}, '_', '_']),
    gen_server_mock:expect_call(Mock, fun({bar, bye}, _From, _State) -> ok end, [{bar, bye}, '_', '_']),

    ok = gen_server:call(Mock, {foo, hi}),  

    Result = try 
                gen_server_mock:assert_expectations(Mock)
            catch
                error:Err -> Err
            end,
    ?assertEqual({unmet_expectations, [{call, [{bar, bye}, '_', '_']}]}, Result).

unexpected_messages_test_not_test() ->
    {ok, Mock} = gen_server_mock:new(),
    gen_server_mock:expect_call(Mock, fun({bar, bye}, _From, _State) -> ok end, [{bar,bye}, '_', '_']),

    unlink(Mock),
    erlang:monitor(process,Mock),
    gen_server:call(Mock, {foo, hi}),
    Result = receive 
                X -> X
             end,
    ?assertEqual(unexpected_request_made, Result).


-ifdef(SKIP).
special_return_values_test_() ->
    {ok, Mock} = gen_server_mock:new(),
    
    gen_server_mock:expect_call(Mock, fun(one,  _From, _State)            -> ok end),
    gen_server_mock:expect_call(Mock, fun(two,  _From,  State)            -> {ok, State} end),
    gen_server_mock:expect_call(Mock, fun(three, _From,  State)           -> {ok, good, State} end),
    gen_server_mock:expect_call(Mock, fun({echo, Response}, _From, State) -> {ok, Response, State} end),
    gen_server_mock:expect_cast(Mock, fun(fish, State) -> {ok, State} end),
    gen_server_mock:expect_info(Mock, fun(cat,  State) -> {ok, State} end),

    ok = gen_server:call(Mock, one),
    ok = gen_server:call(Mock, two),
    good = gen_server:call(Mock, three),
    tree = gen_server:call(Mock, {echo, tree}),
    ok = gen_server:cast(Mock, fish),
    Mock ! cat,

    gen_server_mock:assert_expectations(Mock).
-endif.

-endif.

