import Foundation

struct PetAnimation {
    let id: String
    let displayName: String
    
    static let front = PetAnimation(id: "front", displayName: "Look Forward")
    static let idle = PetAnimation(id: "idle", displayName: "Idle")
    static let eat = PetAnimation(id: "eat", displayName: "Eat")
    static let sleep = PetAnimation(id: "sleep", displayName: "Sleep")
    static let rainCloud = PetAnimation(id: "raincloud", displayName: "Make It Rain")
    static let love = PetAnimation(id: "love", displayName: "Show Love")
    static let angry = PetAnimation(id: "angry", displayName: "Get Angry")
    static let phonecall = PetAnimation(id: "phonecall", displayName: "Take a Call")
    static let worried = PetAnimation(id: "worried", displayName: "Get Worried")
    static let worriedKnife = PetAnimation(id: "worried_knife", displayName: "Worried with Knife")
    static let hammer = PetAnimation(id: "hammer", displayName: "Use Hammer")
    static let chainsawMan = PetAnimation(id: "chainsaw_man", displayName: "Chainsaw Mode")
    static let helmet = PetAnimation(id: "helmet", displayName: "Wear Helmet")
    static let helmetAndTape = PetAnimation(id: "helmet_and_tape", displayName: "Helmet & Tape")
    
    static let all: [PetAnimation] = [
        .front,
        .idle,
        .eat,
        .sleep,
        .rainCloud,
        .love,
        .angry,
        .phonecall,
        .worried,
        .worriedKnife,
        .hammer,
        .chainsawMan,
        .helmet,
        .helmetAndTape
    ]
} 