import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 48,y: 48,width: 928,height: 928), xRadius: 205,yRadius: 205)
NSColor(red: 0.08,green: 0.12,blue: 0.15,alpha: 1).setFill(); background.fill()
let book = NSBezierPath(roundedRect: NSRect(x: 222,y: 365,width: 580,height: 445), xRadius: 40,yRadius: 40)
NSColor(red: 0.95,green: 0.73,blue: 0.42,alpha: 1).setFill(); book.fill()
NSColor(red: 0.075,green: 0.105,blue: 0.125,alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 500,y: 365,width: 20,height: 445)).fill()
for x in [270, 550] { for row in 0..<5 {
    NSBezierPath(roundedRect: NSRect(x:x,y:700-row*54,width:202,height:14),xRadius:7,yRadius:7).fill()
} }
let type = "type" as NSString
type.draw(at: NSPoint(x:285,y:177), withAttributes: [.font:NSFont.monospacedSystemFont(ofSize:145,weight:.semibold),.foregroundColor:NSColor(red:0.87,green:0.9,blue:0.88,alpha:1)])
NSColor(red: 0.95,green: 0.73,blue: 0.42,alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x:680,y:190,width:15,height:125),xRadius:5,yRadius:5).fill()
image.unlockFocus()
for points in [16,32,128,256,512] { for scale in [1,2] {
    let pixels=points*scale
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    image.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels),from:.zero,operation:.copy,fraction:1)
    NSGraphicsContext.restoreGraphicsState()
    let name="icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try rep.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent(name))
} }
