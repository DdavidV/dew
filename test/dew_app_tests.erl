-module(dew_app_tests).

-include_lib("eunit/include/eunit.hrl").

shared_dependency_is_only_walked_once_test() ->
  Table = ets:new(dew_application_shared_dependency_counter, [set, public]),
  Resolver = fun(App) ->
    ets:update_counter(Table, App, {2, 1}, {App, 0}),
    case App of
      a -> [cowboy];
      b -> [cowboy];
      cowboy -> [kernel];
      kernel -> [];
      _ -> []
    end
  end,

  Trees = dew_app:deps([a, b], #{dep_resolver => Resolver}),

  ?assertEqual(1, ets:lookup_element(Table, cowboy, 2)),
  ?assertEqual(1, ets:lookup_element(Table, kernel, 2)),
  ?assertEqual(
    [
      #{application => a,
        dependencies => [
          #{application => cowboy,
            dependencies => [
              #{application => kernel,
                dependencies => []}
            ]
          }
        ]},
      #{application => b,
        dependencies => [
          #{application => cowboy,
            dependencies => [
              #{application => kernel,
                dependencies => []}
            ]}
        ]}
    ],
    Trees
  ).

deep_shared_dependency_is_only_walked_once_test() ->
  Table = ets:new(dew_application_deep_dependency_counter, [set, public]),
  Resolver = fun(App) ->
    ets:update_counter(Table, App, {2, 1}, {App, 0}),
    case App of
      a -> [cowboy];
      b -> [cowboy];
      cowboy -> [ssl, ranch];
      ssl -> [crypto];
      ranch -> [crypto];
      crypto -> [];
      _ -> []
    end
  end,

  Trees = dew_app:deps([a, b], #{dep_resolver => Resolver}),

  ?assertEqual(1, ets:lookup_element(Table, cowboy, 2)),
  ?assertEqual(1, ets:lookup_element(Table, ssl, 2)),
  ?assertEqual(1, ets:lookup_element(Table, ranch, 2)),
  ?assertEqual(1, ets:lookup_element(Table, crypto, 2)),
  ?assertEqual(
    [
      #{application => a,
        dependencies => [
          #{application => cowboy,
            dependencies => [
              #{application => ssl,
                dependencies => [
                  #{application => crypto,
                    dependencies => []}
                ]},
              #{application => ranch,
                dependencies => [
                  #{application => crypto,
                    dependencies => []}
                ]}
            ]}
        ]},
      #{application => b,
        dependencies => [
          #{application => cowboy,
            dependencies => [
              #{application => ssl,
                dependencies => [
                  #{application => crypto,
                    dependencies => []}
                ]},
              #{application => ranch,
                dependencies => [
                  #{application => crypto,
                    dependencies => []}
               ]}
            ]}
        ]}
    ],
    Trees
  ).
dependency_graph_returns_direct_dependency_map_test() ->
  Table = ets:new(dew_application_graph_counter, [set, public]),
  Resolver = fun(App) ->
    ets:update_counter(Table, App, {2, 1}, {App, 0}),
    case App of
      my_app -> [ssl, public_key];
      ssl -> [crypto];
      public_key -> [crypto];
      crypto -> [];
      _ -> []
    end
  end,

  Graph = dew_app:deps(my_app, #{dep_resolver => Resolver, result_type => graph}),

  ?assertEqual(1, ets:lookup_element(Table, ssl, 2)),
  ?assertEqual(1, ets:lookup_element(Table, public_key, 2)),
  ?assertEqual(1, ets:lookup_element(Table, crypto, 2)),
  ?assertEqual(
    #{
      my_app => [ssl, public_key],
      ssl => [crypto],
      public_key => [crypto],
      crypto => []
    },
    Graph
  ).