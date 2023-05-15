//
//  MyOpenCV.h
//  Face Detection
//
//  Created by 신유진 on 2023/05/14.
//  Copyright © 2023 Tomasz Baranowicz. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "MyOpenCV.h"


@interface MyOpenCV : NSObject

+ (NSArray<NSValue *> *)detectEyesInImage:(UIImage *)image;
+ (Boolean) detectIfExistEyesInImage:(UIImage *)image;

@end
