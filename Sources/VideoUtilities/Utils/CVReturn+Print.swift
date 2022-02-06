
import Foundation
import AVFoundation

extension CVReturn {
    func printStatus() {
        switch self {
        case kCVReturnSuccess:
        print("Success")
        case kCVReturnError:
            print("Error:")
        case kCVReturnUnsupported:
            print("Unsupported:")
        case kCVReturnAllocationFailed:
            print("Allocation Failed:")
        case kCVReturnInvalidArgument:
            print("Invalid Argument:")
        case kCVReturnInvalidPixelBufferAttributes:
            print("A buffer cannot be created with the specified attributes.")
        case kCVReturnInvalidPixelFormat:
            print("The buffer does not support the specified pixel format.")
        case kCVReturnInvalidSize:
            print("The buffer cannot support the requested buffer size (usually too big).")
        case kCVReturnPixelBufferNotMetalCompatible:
         //   print(" The pixel buffer is not compatible with Metal due to an unsupported buffer size, pixel format, or attribute.")
        break
        case  kCVReturnPixelBufferNotOpenGLCompatible:
            print("The pixel buffer is not compatible with OpenGL due to an unsupported buffer size, pixel format, or attribute.")
        default:
            print("wtf")
        }
    }
}
