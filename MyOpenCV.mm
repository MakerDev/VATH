//
//  OpenCVWarpper.m
//  Face Detection
//
//  Created by 신유진 on 2023/05/14.
//  Copyright © 2023 Tomasz Baranowicz. All rights reserved.
//

#import "MyOpenCV.h"
#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>

@implementation MyOpenCV


cv::CascadeClassifier eyeCascade;
NSString *cascadePath = [[NSBundle mainBundle] pathForResource:@"haarcascade_eye" ofType:@"xml"];

+ (NSArray<NSValue *> *)detectEyesInImage:(UIImage *)image {
    if (eyeCascade.empty()) {
        if (!eyeCascade.load(std::string([cascadePath UTF8String]))) {
            return @[];
        }
    }

    cv::Mat img;
    UIImageToMat(image, img);
    cv::Mat grayImg;
    cv::cvtColor(img, grayImg, cv::COLOR_BGR2GRAY);
    
    std::vector<cv::Rect> eyes;
    eyeCascade.detectMultiScale(grayImg, eyes, 1.2, 5);
    
    NSMutableArray<NSValue *> *eyeRects = [NSMutableArray arrayWithCapacity:eyes.size()];
    for (const cv::Rect &eyeRect : eyes) {
        CGRect rect = CGRectMake(eyeRect.x, eyeRect.y, eyeRect.width, eyeRect.height);
        [eyeRects addObject:[NSValue valueWithCGRect:rect]];
    }
    
    return [eyeRects copy];
}

+ (Boolean) detectIfExistEyesInImage:(UIImage *)image {
    if (eyeCascade.empty()) {
        if (!eyeCascade.load(std::string([cascadePath UTF8String]))) {
            return false;
        }
    }

    cv::Mat img;
    UIImageToMat(image, img);
    cv::Mat grayImg;
    cv::cvtColor(img, grayImg, cv::COLOR_BGR2GRAY);
    
    std::vector<cv::Rect> eyes;
    eyeCascade.detectMultiScale(grayImg, eyes, 1.2, 5);
    
    return eyes.size() > 0;
}

@end
