import Vapor
import Fluent

final class Profile: Model, Content, @unchecked Sendable {
    
    static let schema: String = "profiles"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "user_id")
    var user: User
    
    @Field(key: "car_owner")
    var carOwner: String
    
    @Field(key: "car_model")
    var carModel: String
    
    @Field(key: "car_regnumber")
    var carRegnumber: String
    
    @Field(key: "vehicle_user")
    var vehicleUser: String
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, userId: UUID, carOwner: String, carModel: String, carRegnumber: String, vehicleUser: String) {
        self.id = id
        self.$user.id = userId
        self.carOwner = carOwner
        self.carModel = carModel
        self.carRegnumber = carRegnumber
        self.vehicleUser = vehicleUser
    }
    
}

