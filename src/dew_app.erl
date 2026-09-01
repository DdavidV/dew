-module(dew_app).

-type application() :: atom().

-type dependency_tree() :: #{
  application := application(),
  dependencies := [dependency_tree()]
}.

-type dependency_graph() :: #{
  application() => [application()]
}.

-type dependency_result() :: dependency_tree() | dependency_graph().

-type dependency_resolver() :: fun((application()) -> [application()]).

-type dependency_result_type() :: tree | graph.

-type options() :: #{
  dep_resolver => dependency_resolver(),
  result_type => dependency_result_type()
}.

-export_type([
  application/0,
  dependency_tree/0,
  dependency_graph/0,
  dependency_result/0,
  dependency_resolver/0,
  dependency_result_type/0,
  options/0
]).

-export([
  deps/0,
  deps/1,
  deps/2
]).

-spec deps() -> Result when
  Result :: dependency_result().
deps() ->
  deps(applications()).

-spec applications() -> Result when
  Result :: [application()].
applications() ->
  [App || {App, _Version, _Description} <- application:loaded_applications()].

-spec deps(ApplicationsOrOptions) -> Result when
  ApplicationsOrOptions :: application() | [application()] | options(),
  Result :: dependency_result().
deps(Applications) when is_list(Applications) ->
  deps(Applications, #{});
deps(Options) when is_map(Options) ->
  deps(applications(), Options);
deps(Application) when is_atom(Application) ->
  deps([Application]).

-spec deps(Applications, Options) -> Result when
  Applications :: application() | [application()],
  Options :: options(),
  Result :: dependency_result().
deps(Application, Options) when is_atom(Application) ->
  deps([Application], Options);
deps(Applications, Options) when is_list(Applications) andalso is_map(Options) ->
  Resolver = maps:get(dep_resolver, Options, fun dependencies/1),
  Trees = build_dependency_trees(Applications, #{}, Resolver, []),
  Type = maps:get(result_type, Options, tree),
  format_dependencies(Type, Trees).

format_dependencies(tree, Trees) ->
  Trees;
format_dependencies(graph, Trees) ->
  lists:foldl(fun build_dependency_graph/2, #{}, Trees).

build_dependency_graph([], Graph) ->
  Graph;
build_dependency_graph(#{application := App, dependencies := Dependencies}, Graph0) ->
  Graph = Graph0#{App => [Name || #{application := Name} <- Dependencies]},
  lists:foldl(fun build_dependency_graph/2, Graph, Dependencies).

build_dependency_trees([], _Cache, _Resolver, Acc) ->
  lists:reverse(Acc);
build_dependency_trees([App | Rest], Cache, Resolver, Acc) ->
  {Tree, Cache1} = build_dependency_tree(App, Resolver, Cache),
  build_dependency_trees(Rest, Cache1, Resolver, [Tree | Acc]).

build_dependency_tree(App, Resolver, Cache) ->
  case maps:get(App, Cache, undefined) of
    undefined ->
      Placeholder = #{application => App, dependencies => []},
      Cache1 = Cache#{App => Placeholder},
      Dependencies = Resolver(App),
      {Subtrees, Cache2} = build_subtrees(Dependencies, Resolver, Cache1),
      Tree = Placeholder#{dependencies => Subtrees},
      {Tree, Cache2#{App => Tree}};
    Tree ->
      {Tree, Cache}
  end.

build_subtrees([], _Resolver, Cache) ->
  {[], Cache};
build_subtrees([App | Rest], Resolver, Cache) ->
  {Tree, Cache1} = build_dependency_tree(App, Resolver, Cache),
  {Trees, Cache2} = build_subtrees(Rest, Resolver, Cache1),
  {[Tree | Trees], Cache2}.

dependencies(App) ->
  case application:get_key(App, applications) of
    {ok, Applications} ->
      Applications;
    undefined ->
      []
  end.
