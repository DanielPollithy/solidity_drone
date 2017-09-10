pragma solidity ^0.4.0;

// Todos:
//      - calculate price and payment
//      - add events
//      - check station params (0<= clock_in/out times <= 47)

// Another approach to the DroneChain charging registry
// Based on the assumption that 24 hours á 2 slots per hour 
// is enough accuracy for a booking system

// Note: The drone, the station and the booking can store addresses 
// for authentification (see IoT thing)
// but they don't necessarily need an own contract.


contract StationContract {
    address owner;
    function StationContract() {
        owner = msg.sender;
    }
}

contract DroneContract {
    address owner;
    function DroneContract() {
        owner = msg.sender;
    }
}

contract BookingContract {
    address owner;
    function BookingContract(address drone) {
        owner = drone;
    }
}

contract Register {
    struct Drone {
        bool active;
        address drone_contract;
        address owner;
        address[48] bookings;
    }
    
    struct Booking {
        address station;
        address drone;
        uint timestamp;
    }
    
    struct Station {
        bool active;
        address station_contract;
        address owner;
        uint8 lat;
        uint8 long;
        // time slot minimum which is allowed
        // example: clock_in = 12 -> 6:00 is the first available slot
        uint8 clock_in;
        // time slot maximum which is allowed
        // example: clock_out = 36 -> 18:00 is the latest available slot 
        uint8 clock_out;
        uint8 price_per_kwh;
        // a charging may take 30 minutes
        // the system shall enable bookings for one day
        // provide an array of: 1 day x 24 hours x 2 charging slots
        // example: index=0 -> 0:00 - 0:30, index=1 -> 0:30 - 1:00
        address[48] bookings;
    }
    
    struct Person {
        address wallet;
        address[] drones;
        address[] stations;
        // additional information e.g. preferences for the stations...
        // payment intervals or ratings
    }
    
    mapping(address => Person) personRegister;
    mapping(address => Drone) droneRegister;
    mapping(address => Station) stationRegister;
    mapping(address => Booking) bookingRegister;
    
    address admin;
    
    // register a person which can be an owner of drones or stations
    function _setPerson() private {
        if(personRegister[msg.sender].wallet != 0) {
            personRegister[msg.sender].wallet = msg.sender; 
        }
    }
    
    // Create a new Register with the administrator
    function Register() {
        admin = msg.sender;
    }
    
    function droneExists (address drone) returns (bool) {
        return droneRegister[drone].drone_contract != 0;
    }
    
    function stationExists (address station) returns (bool) {
        return stationRegister[station].station_contract != 0;
    }
    
    function droneOwnedBySender (address drone) returns (bool) {
        return droneRegister[drone].owner == msg.sender;
    }
    
    function stationOwnedBySender (address station) returns (bool) {
        return stationRegister[station].owner == msg.sender;
    }
    
    function timeToSlot (uint time) returns (uint8) {
        return uint8((time % 86400) / (60 * 60 / 2));
    }
    
    // Get the current booking of a station
    function getBookingForStation(address station) 
        returns (bool exists, address booking_addr){
        assert(stationExists(station));
        assert(stationOwnedBySender(station));
        uint8 targetSlot = timeToSlot(now);
        if (bookingRegister[stationRegister[station].bookings[targetSlot]].timestamp >= targetSlot * 86400) {
            return (true, stationRegister[station].bookings[targetSlot]);
        }
        return (false, address(0));
    }
    
    // Get the next bookings of a drone
    function getBookingsForDrone(address drone) 
        returns (address[48] booking_addresses){
            assert(droneExists(drone));
            assert(droneOwnedBySender(drone));
            return droneRegister[drone].bookings;
    }
    
    // returns a booking or null
    // unixtime in POSIX +0
    function makeBooking(address drone, address station, uint unixtime) returns (uint8){
        // assert existance
        assert(droneExists(drone));
        assert(stationExists(station));
        assert(msg.sender == droneRegister[drone].owner);
        
        // we are going to use the miner's now 
        // (assuming that this is going to be reliable in the future)
        uint now_time = now;
        
        // assert booking is in the future
        assert(unixtime > now_time);
        // assert booking is maximum of 24 hours in the future
        assert(unixtime < (now_time + 60*60*24));
        
        // calculate the current slot
        // seconds of the day (-> leap seconds ignored)
        // uint8 currentSlot = timeToSlot(now_time);
        uint8 targetSlot = timeToSlot(unixtime);
        
        // check whether the slot is okay for the clock_in of the station
        assert(targetSlot >= stationRegister[station].clock_in);
        // check for the clock_out
        assert(targetSlot <= stationRegister[station].clock_out);
        
        // absolute slot is used to build an absolute order
        uint target_absolute_slot = targetSlot * 86400;
        
        // if there is already a booking assert that it aged out
        if (bookingRegister[stationRegister[station].bookings[targetSlot]].timestamp != 0) {
           assert(bookingRegister[stationRegister[station].bookings[targetSlot]].timestamp < target_absolute_slot);
        } 
        // create a new booking
        address bookingAddress = new BookingContract(drone);
        
        // now store the booking in the station
        stationRegister[station].bookings[targetSlot] = bookingAddress;
        
        // and add the information to the booking registry
        bookingRegister[stationRegister[station].bookings[targetSlot]].timestamp = target_absolute_slot;
        bookingRegister[stationRegister[station].bookings[targetSlot]].station = station;
        bookingRegister[stationRegister[station].bookings[targetSlot]].drone = drone;
        
        // store the booking in the drone's register
        droneRegister[drone].bookings[targetSlot] = stationRegister[station].bookings[targetSlot];
        return targetSlot;
    }
    
    function addDrone() returns (address) {
        _setPerson();
        // now create a new drone contact
        address droneAddress = new DroneContract();
        // store the drone in the drone register
        droneRegister[droneAddress].active = true;
        droneRegister[droneAddress].drone_contract = droneAddress;
        droneRegister[droneAddress].owner = msg.sender;
        // add the drone to the person's drone array
        personRegister[msg.sender].drones.push(droneAddress);
        return droneAddress;
    }
    
    function addStation(uint8 lat, uint8 long, uint8 clock_in, uint8 clock_out, 
                        uint8 price_per_kwh) returns (address) {
        _setPerson();
        // now create a new station contract
        address stationAddress = new StationContract();
        // store the drone in the drone register
        stationRegister[stationAddress].active = true;
        stationRegister[stationAddress].lat = lat;
        stationRegister[stationAddress].long = long;
        stationRegister[stationAddress].clock_in = clock_in;
        stationRegister[stationAddress].clock_out = clock_out;
        stationRegister[stationAddress].price_per_kwh = price_per_kwh;
        stationRegister[stationAddress].station_contract = stationAddress;
        stationRegister[stationAddress].owner = msg.sender;
        // add the drone to the person's drone array
        personRegister[msg.sender].stations.push(stationAddress);
        return stationAddress;
    }
}
