#ifndef __NOXIMROUTING_OCTAGON_H__
#define __NOXIMROUTING_OCTAGON_H__

#include "RoutingAlgorithm.h"
#include "RoutingAlgorithms.h"
#include "../Router.h"

using namespace std;

class Routing_OCTAGON : RoutingAlgorithm {
    public:
        vector<int> route(Router *router, const RouteData &routeData);

        static Routing_OCTAGON *getInstance();

    private:
        Routing_OCTAGON() {}
        ~Routing_OCTAGON() {}

        static Routing_OCTAGON *routing_OCTAGON;
        static RoutingAlgorithmsRegister routingAlgorithmsRegister;
};

#endif
