#include "Routing_XY_TORUS.h"

RoutingAlgorithmsRegister Routing_XY_TORUS::routingAlgorithmsRegister("XY_TORUS", getInstance());

Routing_XY_TORUS * Routing_XY_TORUS::routing_XY_TORUS = 0;

Routing_XY_TORUS * Routing_XY_TORUS::getInstance() {
	if ( routing_XY_TORUS == 0 )
		routing_XY_TORUS = new Routing_XY_TORUS();
    
	return routing_XY_TORUS;
}

vector<int> Routing_XY_TORUS::route(Router * router, const RouteData & routeData)
{
    Coord current = id2Coord(routeData.current_id);
    Coord destination = id2Coord(routeData.dst_id);
    vector <int> directions;

    int dim_x = GlobalParams::mesh_dim_x;
    int dim_y = GlobalParams::mesh_dim_y;

    // Compute deltas
    int dx = destination.x - current.x;
    int dy = destination.y - current.y;

    // Adjust deltas for wrap-around in torus topology
    if (dx > dim_x / 2)
        dx -= dim_x;
    else if (dx < -dim_x / 2)
        dx += dim_x;

    if (dy > dim_y / 2)
        dy -= dim_y;
    else if (dy < -dim_y / 2)
        dy += dim_y;

    // Dimension-order routing (X first, then Y)
    if (dx > 0)
        directions.push_back(DIRECTION_EAST);
    else if (dx < 0)
        directions.push_back(DIRECTION_WEST);
    else if (dy > 0)
        directions.push_back(DIRECTION_SOUTH);
    else if (dy < 0)
        directions.push_back(DIRECTION_NORTH);

    return directions;
   } 
