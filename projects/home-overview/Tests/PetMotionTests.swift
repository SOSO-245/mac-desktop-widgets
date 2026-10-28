import Foundation
@main struct PetMotionTests {
 static func main() {
  var motion=DuckProgressMotion();motion.reset(to:0.2,at:0);motion.retarget(0.8,at:1)
  precondition(abs(motion.value(at:1)-0.2)<1e-8,"new sample must not teleport")
  precondition(motion.value(at:1.2)>0.2 && motion.value(at:1.2)<0.8)
  var previous=motion.value(at:1)
  for i in 1...120 {let next=motion.value(at:1+Double(i)/30);precondition(next>=previous && next<=0.8);previous=next}
  let mid=motion.value(at:1.3);motion.retarget(0.1,at:1.3)
  precondition(abs(motion.value(at:1.3)-mid)<1e-8,"retarget preserves current position")
  var time=1.3
  for i in 0..<300 {time+=0.1;let before=motion.value(at:time);motion.retarget(Double(i%11)/10,at:time);precondition(abs(before-motion.value(at:time))<1e-8);precondition((0...1).contains(motion.value(at:time+0.05)))}
  let now=Date(timeIntervalSince1970:1_790_000_000)
  precondition(BirthdayBadgeSignal.isActive(.init(active:true,generatedAt:now.timeIntervalSince1970,validUntil:now.timeIntervalSince1970+3600),at:now))
  precondition(!BirthdayBadgeSignal.isActive(.init(active:true,generatedAt:now.timeIntervalSince1970,validUntil:now.timeIntervalSince1970),at:now))
  precondition(!BirthdayBadgeSignal.isActive(nil,at:now))
  print("PASS: continuous progress across 300 retargets, bounded motion, birthday expiration")
 }
}
