
n <- 300
x1 <- rnorm(n)
x2 <- rnorm(n)
x3 <- rnorm(n)

summary(p1 <- plogis(2 +0.5*x1 -2*x2))
summary(mu.pos <- exp(1 -0.5*x1 +1*x3))

table(z <- rbinom(n, 1, p1))
summary(y <- ifelse(z==1, rpois(n, mu.pos), NA))
tapply(y, z, summary)

table(iy0 <- (z==1) & (y==0)) ### where y is zero and z is 1
while(sum(iy0)>0) { ## truncating
    y[iy0] <- rpois(sum(iy0), mu.pos[iy0])
    iy0 <- (z==1) & (y==0)
}
tapply(y, z, summary)

library(INLA)

### model separately
res.z <- inla(z ~ x1 + x2 + x3, 'binomial', data=list(x1=x1, x2=x2, x3=x3, z=z))
res.y <- inla(y ~ x1 + x2 + x3, 'zeroinflatedpoisson0',
              data=list(x1=x1, x2=x2, x3=x3, y=y), 
              control.family=list(hyper=list(theta=list(intial=10, fixed=TRUE))))
round(cbind(c(2,.5,-2,0), res.z$summary.fix[, 1:5]), 4)
round(cbind(c(1,-.5,0,1), res.y$summary.fix[, 1:5]), 4)

### model jointly
dat <- list(Y=rbind(cbind(z, NA), cbind(NA, y)))
dat$az <- rep(1:0, c(n, n))
dat$x1z <- c(x1, rep(0, n))
dat$x2z <- c(x2, rep(0, n))
dat$x3z <- c(x3, rep(0, n))
dat$ay <- rep(0:1, c(n, n))
dat$x1y <- c(rep(0, n), x1)
dat$x2y <- c(rep(0, n), x2)
dat$x3y <- c(rep(0, n), x3)

res.zy <- inla(Y ~ 0 + az + x1z + x2z + x3z + ay + x1y + x2y + x3y,
               family=c('binomial', 'zeroinflatedpoisson0'), data=dat, 
               control.family=list(list(),
                                   list(hyper=list(theta=list(intial=10, fixed=TRUE)))))

round(cbind(true=c(2, .5,-2,0, 1,-.5,0,1),
            res.zy$summary.fix[, 1:5]), 4)
