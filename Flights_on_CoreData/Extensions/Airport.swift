//
//  Airport.swift
//  Flights_on_CoreData
//
//  Created by NewUSER on 17.05.2021.
//

import CoreData
import Combine


extension Airport {
    static func withICAO(_ icao: String, context: NSManagedObjectContext) -> Airport {
        //trying to find and create otherwise
        let request = fetchRequest(NSPredicate(format: "icao_ = %@", icao))
        let airport = (try? context.fetch(request)) ?? [] //if err then nil, if no record then empty array, or records
        
        if let airport = airport.first {
            return airport
        } else {
            //if no airport in db then create on and fetch from FlightAware
            let airport = Airport(context: context)
            airport.icao = icao
            
            AirportInfoRequest.fetch(icao) { airport in
                update(from: airport, context: context)
            }
            return airport //returning airport just with icoa, then will be update aync way
        }
        
    }
    
    static func update(from info:AirportInfo, context: NSManagedObjectContext){
        if let icao = info.icao {
            let airport = self.withICAO(icao, context: context)
            airport.latitude = info.latitude
            airport.longitude = info.longitude
            airport.name = info.name
            airport.location = info.location
            airport.timezone = info.timezone
            
            //Airport is Observable
            airport.objectWillChange.send() //so any view that is pointing to airport will be redrawn
            
            /*
             originally
            airport.flightsTo?.forEach {$0.objectWillChange.send()}
            cause /Value of type 'NSSet.Element' (aka 'Any') has no member 'objectWillChange'/ err
            because flightsTo is NSSet? type. Force unwrapping of flightsTo will net help since it is NSSet.Element (Any) type. Need some syntatic sugar by computed var. Need rename references in DataCore by underbar
            */
            
            airport.flightsTo.forEach{$0.objectWillChange.send()}
            airport.flightsFrom.forEach{$0.objectWillChange.send()}
            try? context.save()
        }
    }
    
    var flightsTo: Set<Flight> {
        get { (flightsTo_ as? Set<Flight>) ?? []}
        set { flightsTo_ = newValue as NSSet}
    }
    var flightsFrom: Set<Flight> {
        get { (flightsFrom_ as? Set<Flight>) ?? []}
        set { (flightsFrom_ = newValue as NSSet )}
    }
}

extension Airport: Comparable {
    var icao: String {
        get { icao_! } //this never should be nill but needs some protection for production
        set { icao_ = newValue}
    }
    
    var friendlyName: String {
        let friendly = AirportInfo.friendlyName(name: name ?? "", location: location ?? "")
        return friendly.isEmpty ? icao : friendly
    }
    
    public var id: String {icao}
    
    public static func < (lhs: Airport, rhs: Airport) -> Bool {
        lhs.location ?? lhs.friendlyName < rhs.location ?? rhs.friendlyName
    }

    static func fetchRequest(_ predicate: NSPredicate) -> NSFetchRequest<Airport> {
        let request = NSFetchRequest<Airport>(entityName: "Airport")
        request.sortDescriptors = [NSSortDescriptor(key: "location", ascending: true)]
        request.predicate = predicate
        return request
    }

    func fetchIncoingFlights() {
        Self.flightAwareRequest?.stopFetching()
        if let context = managedObjectContext {
            Self.flightAwareRequest = EnrouteRequest.create(airport: icao, howMany: 120)
            Self.flightAwareRequest?.fetch(andRepeatEvery: 10)
            Self.flightAwareResultCancellable = Self.flightAwareRequest?.results.sink { results in
                for faflight in results {
                    Flight.update(from: faflight, in: context)
                }
                do {
                    try context.save()
                } catch (let error){
                    print("could not save flight update to CoreData: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private static var flightAwareRequest: EnrouteRequest!
    private static var flightAwareResultCancellable: AnyCancellable?
}

