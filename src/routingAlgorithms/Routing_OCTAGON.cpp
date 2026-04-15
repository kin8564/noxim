#include "Routing_OCTAGON.h"

#include <queue>

RoutingAlgorithmsRegister Routing_OCTAGON::routingAlgorithmsRegister("OCTAGON", getInstance());

Routing_OCTAGON *Routing_OCTAGON::routing_OCTAGON = 0;

Routing_OCTAGON *Routing_OCTAGON::getInstance()
{
    if (routing_OCTAGON == 0)
        routing_OCTAGON = new Routing_OCTAGON();

    return routing_OCTAGON;
}

vector<int> Routing_OCTAGON::route(Router *router, const RouteData &routeData)
{
    vector<int> directions;

    if (GlobalParams::topology != TOPOLOGY_OCTAGON) {
        directions.push_back(DIRECTION_EAST);
        return directions;
    }

    const int current = routeData.current_id;
    const int destination = routeData.dst_id;

    if (current < 0 || current >= 8 || destination < 0 || destination >= 8) {
        directions.push_back(DIRECTION_EAST);
        return directions;
    }

    if (current == destination) {
        directions.push_back(DIRECTION_LOCAL);
        return directions;
    }

    const int INVALID = -1;
    const int n = 8;

    const int neighbor[n][DIRECTIONS] = {
        {INVALID, 1, 4, 7},
        {INVALID, 2, 5, 0},
        {INVALID, 3, 6, 1},
        {4, INVALID, 7, 2},
        {0, 5, 3, INVALID},
        {1, 6, INVALID, 4},
        {2, 7, INVALID, 5},
        {3, 0, INVALID, 6}
    };

    int dist[n];
    for (int i = 0; i < n; i++)
        dist[i] = INVALID;

    queue<int> q;
    dist[destination] = 0;
    q.push(destination);

    while (!q.empty()) {
        int node = q.front();
        q.pop();

        for (int d = 0; d < DIRECTIONS; d++) {
            int prev = neighbor[node][d];
            if (prev == INVALID)
                continue;
            if (dist[prev] != INVALID)
                continue;

            dist[prev] = dist[node] + 1;
            q.push(prev);
        }
    }

    int best_direction = INVALID;
    int best_distance = 1 << 30;

    for (int d = 0; d < DIRECTIONS; d++) {
        int next = neighbor[current][d];
        if (next == INVALID)
            continue;
        if (dist[next] == INVALID)
            continue;
        if (dist[next] < best_distance) {
            best_distance = dist[next];
            best_direction = d;
        }
    }

    if (best_direction == INVALID)
        best_direction = DIRECTION_EAST;

    directions.push_back(best_direction);
    return directions;
}
