//
//  ViewController.m
//  RecordDemo
//
//  Created by SZOeasy on 2018/12/10.
//  Copyright © 2018年 yilingyijia. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

#define ScreenW [UIScreen mainScreen].bounds.size.width
#define ScreenH [UIScreen mainScreen].bounds.size.height

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>
{
    int frameID;
    VTCompressionSessionRef EncodingSession;
    dispatch_queue_t mEncodeQueue;
    NSFileHandle *fileHandle;
}
@property (strong, nonatomic) AVCaptureSession *captureSession;
//@property (strong, nonatomic) UIImageView *imageView;
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *previewLayer;

@property (strong, nonatomic) UIButton *encodeButton;
@property (assign, nonatomic) BOOL encodeFlag;

@end

static int count = 0;

@implementation ViewController

#pragma mark - Life Cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    self.encodeFlag = NO;
    
    self.encodeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.encodeButton.frame = CGRectMake(100, 200, 200, 50);
    [self.encodeButton setBackgroundColor:[UIColor grayColor]];
    [self.encodeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.encodeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
    [self.encodeButton setTitle:@"开始" forState:UIControlStateNormal];
    [self.encodeButton setTitle:@"编码中" forState:UIControlStateSelected];
    self.encodeButton.selected = NO;
    [self.encodeButton addTarget:self action:@selector(encodeVideo) forControlEvents:UIControlEventTouchUpInside];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self initConfig];
    
    [self.view addSubview:self.encodeButton];
    
    mEncodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
}

- (void)initConfig {
    // 设置会话，分辨率
    _captureSession = [[AVCaptureSession alloc] init];
    _captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
    
    // 设置输入对象，帧率
    AVCaptureDevice *videoDevice = [self cameraWithPostion:AVCaptureDevicePositionBack];
    
    NSError *error;
    CMTime frameDuration = CMTimeMake(1, 60);
    NSArray *supportedFrameRateRanges = [videoDevice.activeFormat videoSupportedFrameRateRanges];
    BOOL frameRateSupported = NO;
    for (AVFrameRateRange *range in supportedFrameRateRanges) {
        if (CMTIME_COMPARE_INLINE(frameDuration, >=, range.minFrameDuration) &&
            CMTIME_COMPARE_INLINE(frameDuration, <=, range.maxFrameDuration)) {
            frameRateSupported = YES;
        }
    }
    if (frameRateSupported && [videoDevice lockForConfiguration:&error]) {
        [videoDevice setActiveVideoMaxFrameDuration:frameDuration];
        [videoDevice setActiveVideoMinFrameDuration:frameDuration];
        [videoDevice unlockForConfiguration];
    }
    
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    
    if ([_captureSession canAddInput:videoInput]) {
        [_captureSession addInput:videoInput];
    }
    
    // 设置输出，帧率，yuv格式
    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
//    videoOutput.minFrameDuration = CMTimeMake(1, 10);
//    videoOutput.videoSettings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
    [videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey]];
    // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // 420sp nv12
   
    // 设置代理，获取帧数据
    dispatch_queue_t queue = dispatch_queue_create("YcongSerialQueue", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:self queue:queue];
    
    if([_captureSession canAddOutput:videoOutput]) {
        // 给会话添加输入输出就会自动建立起连接
        [_captureSession addOutput:videoOutput];
    }
    
    // 注意： 一定要在添加之后
    // 获取输入与输出之间的连接
//    AVCaptureConnection *connection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
//    // 设置采集数据的方向、镜像
//    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
//    connection.videoMirrored = YES;
    
    _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.captureSession];
    _previewLayer.frame = CGRectMake(0, 20, self.view.frame.size.width, self.view.frame.size.height - 20);
    [self.view.layer addSublayer:self.previewLayer];

    
    // 开启会话
    // 一开启会话，就会在输入与输出对象之间建立起连接
    [_captureSession startRunning];
}

#pragma mark - Action
- (void)encodeVideo {
    self.encodeButton.selected = !self.encodeButton.selected;
    if (self.encodeButton.selected) {
        NSLog(@"编码----");
        NSString *file = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"1234.h264"];
        [[NSFileManager defaultManager] removeItemAtPath:file error:nil];
        [[NSFileManager defaultManager] createFileAtPath:file contents:nil attributes:nil];
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:file];
        [self initVideoToolBox];
    } else {
        NSLog(@"结束----");
        self.encodeFlag = NO;
        [self EndVideoToolBox];
        [fileHandle closeFile];
        fileHandle = NULL;
    }
}

#pragma mark - <AVCaptureVideoDataOutputSampleBufferDelegate>
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (self.encodeFlag) {
        dispatch_sync(mEncodeQueue, ^{
            [self encode:sampleBuffer];
        });
    }
//    NSLog(@"----- didOutputSampleBuffer ----- %d", count++);
//    
//    if (count == 10) {
//        // 获取图片帧数据
//        CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
//        void *baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer,0);
//        void *uv = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer,1);
//        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
//
//        size_t width = CVPixelBufferGetWidth(pixelBuffer);
//        size_t height = CVPixelBufferGetHeight(pixelBuffer);
//        NSLog(@"%ld,%ld", width, height);
//
//        Byte *buf = malloc(width*height*3/2);
//        memcpy(buf, baseAddress, width*height);
//        size_t a = width * height;
//        size_t b = width * height * 5 / 4;
//        for (NSInteger i = 0; i < width * height/ 2; i ++) {
//            memcpy(buf + a, uv + i , 1);
//            a++;
//            i++;
//            memcpy(buf + b, uv + i, 1);
//            b++;
//        }
//
//        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
//        NSString *filepath = [docPath stringByAppendingString:[NSString stringWithFormat:@"/%@.yuv", [self getCurrentTimes]]];
//        NSFileManager *fileManager = [NSFileManager defaultManager];
//        if (![fileManager fileExistsAtPath:filepath]) {
//            [fileManager createFileAtPath:filepath contents:nil attributes:nil];
//        } else {
//            [fileManager removeItemAtPath:filepath error:nil];
//            [fileManager createFileAtPath:filepath contents:nil attributes:nil];
//        }
//        FILE *fp = fopen(filepath.UTF8String, "wb");
//        fwrite(buf, 1, width*height*3/2, fp);
//        fclose(fp);
//    }

   
//    CIImage *ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];
//    UIImage *image = [UIImage imageWithCIImage:ciImage];
//
//    dispatch_async(dispatch_get_main_queue(), ^{
//        self.imageView.image = image;
//    });
    
//    NSLog(@"----- sampleBuffer ----- %d", count++);
}

- (void)initVideoToolBox {
    dispatch_sync(mEncodeQueue  , ^{
        frameID = 0;
        int width = 1920, height = 1080;
        OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)(self),  &EncodingSession);
        NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
        if (status != 0)
        {
            NSLog(@"H264: Unable to create a H264 session");
            return ;
        }
        
        // 设置实时编码输出（避免延迟）
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        
        // 设置关键帧（GOPsize)间隔
        int frameInterval = 10;
        CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
        
        // 设置期望帧率
        int fps = 10;
        CFNumberRef  fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
        
        
        //设置码率，均值，单位是byte
        int bitRate = width * height * 3 * 4 * 8;
        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
        
        //设置码率，上限，单位是bps
        int bitRateLimit = width * height * 3 * 4;
        CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRateLimit);
        VTSessionSetProperty(EncodingSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
        
        // Tell the encoder to start encoding
        VTCompressionSessionPrepareToEncodeFrames(EncodingSession);
        self.encodeFlag = YES;
    });
}

- (void)encode:(CMSampleBufferRef )sampleBuffer {
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    // 帧时间，如果不设置会导致时间轴过长。
    CMTime presentationTimeStamp = CMTimeMake(frameID++, 1000);
    VTEncodeInfoFlags flags;
    OSStatus statusCode = VTCompressionSessionEncodeFrame(EncodingSession,
                                                          imageBuffer,
                                                          presentationTimeStamp,
                                                          kCMTimeInvalid,
                                                          NULL, NULL, &flags);
    if (statusCode != noErr) {
        NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
        
        VTCompressionSessionInvalidate(EncodingSession);
        CFRelease(EncodingSession);
        EncodingSession = NULL;
        return;
    }
    NSLog(@"H264: VTCompressionSessionEncodeFrame Success");
}

void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags);
    if (status != 0) {
        return;
    }
    
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    ViewController* encoder = (__bridge ViewController*)outputCallbackRefCon;
    NSLog(@"ycong:123");

    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    // 判断当前帧是否为关键帧
    // 获取sps & pps数据
    if (keyframe)
    {
        NSLog(@"ycong:keyframe");
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        if (statusCode == noErr)
        {
            // Found sps and now check for pps
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            if (statusCode == noErr)
            {
                // Found pps
                NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                if (encoder)
                {
                    [encoder gotSpsPps:sps pps:pps];
                }
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        NSLog(@"ycong:statusCodeRet == noErr");

        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4; // 返回的nalu数据前四个字节不是0001的startcode，而是大端模式的帧长度length
        
        // 循环获取nalu数据
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            uint32_t NALUnitLength = 0;
            // Read the NAL unit length
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // 从大端转系统端
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            [encoder gotEncodedData:data isKeyFrame:keyframe];
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}

- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps {
    NSLog(@"ycong:gotSpsPps");

    NSLog(@"gotSpsPps %d %d", (int)[sps length], (int)[pps length]);
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    [fileHandle writeData:ByteHeader];
    [fileHandle writeData:sps];
    [fileHandle writeData:ByteHeader];
    [fileHandle writeData:pps];
    
}

- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame {
    NSLog(@"ycong:gotEncodedData");

    NSLog(@"gotEncodedData %d", (int)[data length]);
    if (fileHandle != NULL)
    {
        const char bytes[] = "\x00\x00\x00\x01";
        size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
        NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
        [fileHandle writeData:ByteHeader];
        [fileHandle writeData:data];
    }
}

- (void)EndVideoToolBox {
    VTCompressionSessionCompleteFrames(EncodingSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(EncodingSession);
    CFRelease(EncodingSession);
    EncodingSession = NULL;
}

- (AVCaptureDevice *)cameraWithPostion:(AVCaptureDevicePosition)position{
    AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:position];
    NSArray *devicesIOS  = discoverySession.devices;
    for (AVCaptureDevice *device in devicesIOS) {
        if ([device position] == position) {
            return device;
        }
    }

    return nil;
}

- (NSString*)getCurrentTimes {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss"];
    NSDate *datenow = [NSDate date];
    NSString *currentTimeString = [formatter stringFromDate:datenow];

    return currentTimeString;
}

@end
