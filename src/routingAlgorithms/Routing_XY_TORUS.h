#ifndef __NOXIMROUTING_XY_TORUS_H__
#define __NOXIMROUTING_XY_TORUS_H__

#include "RoutingAlgorithm.h"
#include "RoutingAlgorithms.h"
#include "../Router.h"

using namespace std;

class Routing_XY_TORUS : RoutingAlgorithm {
	public:
		vector<int> route(Router * router, const RouteData & routeData);

		static Routing_XY_TORUS * getInstance();

	private:
		Routing_XY_TORUS(){};
		~Routing_XY_TORUS(){};

		static Routing_XY_TORUS * routing_XY_TORUS;
		static RoutingAlgorithmsRegister routingAlgorithmsRegister;
};

#endif
