package objstore

import (
	"context"
	"fmt"
	"io"
	"strconv"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// S3Config configures the SeaweedFS S3 client.
type S3Config struct {
	Endpoint        string
	Region          string
	Bucket          string
	AccessKeyID     string
	SecretAccessKey string
}

// S3Store talks to a SeaweedFS S3 gateway using path-style addressing.
type S3Store struct {
	client *s3.Client
	bucket string
}

// NewS3 builds an S3Store from config.
func NewS3(cfg S3Config) (*S3Store, error) {
	if cfg.Endpoint == "" || cfg.Bucket == "" {
		return nil, fmt.Errorf("objstore: S3 endpoint and bucket are required")
	}
	region := cfg.Region
	if region == "" {
		region = "us-east-1"
	}
	client := s3.New(s3.Options{
		Region:       region,
		BaseEndpoint: aws.String(cfg.Endpoint),
		UsePathStyle: true, // SeaweedFS serves buckets path-style.
		Credentials: credentials.NewStaticCredentialsProvider(
			cfg.AccessKeyID, cfg.SecretAccessKey, "",
		),
	})
	return &S3Store{client: client, bucket: cfg.Bucket}, nil
}

func (s *S3Store) PutObject(ctx context.Context, key string, body io.Reader, size int64) error {
	_, err := s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(s.bucket),
		Key:           aws.String(key),
		Body:          body,
		ContentLength: aws.Int64(size),
	})
	if err != nil {
		return fmt.Errorf("objstore: put %s: %w", key, err)
	}
	return nil
}

func (s *S3Store) GetObjectRange(ctx context.Context, key string, off, length int64) (io.ReadCloser, *ObjectInfo, error) {
	in := &s3.GetObjectInput{Bucket: aws.String(s.bucket), Key: aws.String(key)}
	if off > 0 || length >= 0 {
		if length >= 0 {
			in.Range = aws.String("bytes=" + strconv.FormatInt(off, 10) + "-" + strconv.FormatInt(off+length-1, 10))
		} else {
			in.Range = aws.String("bytes=" + strconv.FormatInt(off, 10) + "-")
		}
	}
	out, err := s.client.GetObject(ctx, in)
	if err != nil {
		return nil, nil, fmt.Errorf("objstore: get %s: %w", key, err)
	}
	info := &ObjectInfo{}
	if out.ContentLength != nil {
		info.Size = *out.ContentLength
	}
	if out.ETag != nil {
		info.ETag = *out.ETag
	}
	if out.LastModified != nil {
		info.LastModified = *out.LastModified
	}
	return out.Body, info, nil
}

func (s *S3Store) HeadObject(ctx context.Context, key string) (*ObjectInfo, error) {
	out, err := s.client.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return nil, fmt.Errorf("objstore: head %s: %w", key, err)
	}
	info := &ObjectInfo{}
	if out.ContentLength != nil {
		info.Size = *out.ContentLength
	}
	if out.ETag != nil {
		info.ETag = *out.ETag
	}
	if out.LastModified != nil {
		info.LastModified = *out.LastModified
	}
	return info, nil
}

func (s *S3Store) CreateMultipart(ctx context.Context, key string) (string, error) {
	out, err := s.client.CreateMultipartUpload(ctx, &s3.CreateMultipartUploadInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return "", fmt.Errorf("objstore: create multipart %s: %w", key, err)
	}
	return aws.ToString(out.UploadId), nil
}

func (s *S3Store) UploadPart(ctx context.Context, key, uploadID string, partNumber int32, body io.Reader, size int64) (string, error) {
	out, err := s.client.UploadPart(ctx, &s3.UploadPartInput{
		Bucket:        aws.String(s.bucket),
		Key:           aws.String(key),
		UploadId:      aws.String(uploadID),
		PartNumber:    aws.Int32(partNumber),
		Body:          body,
		ContentLength: aws.Int64(size),
	})
	if err != nil {
		return "", fmt.Errorf("objstore: upload part %d of %s: %w", partNumber, key, err)
	}
	return aws.ToString(out.ETag), nil
}

func (s *S3Store) CompleteMultipart(ctx context.Context, key, uploadID string, parts []CompletedPart) error {
	completed := make([]types.CompletedPart, 0, len(parts))
	for _, p := range parts {
		completed = append(completed, types.CompletedPart{
			PartNumber: aws.Int32(p.PartNumber),
			ETag:       aws.String(p.ETag),
		})
	}
	_, err := s.client.CompleteMultipartUpload(ctx, &s3.CompleteMultipartUploadInput{
		Bucket:          aws.String(s.bucket),
		Key:             aws.String(key),
		UploadId:        aws.String(uploadID),
		MultipartUpload: &types.CompletedMultipartUpload{Parts: completed},
	})
	if err != nil {
		return fmt.Errorf("objstore: complete multipart %s: %w", key, err)
	}
	return nil
}

func (s *S3Store) AbortMultipart(ctx context.Context, key, uploadID string) error {
	_, err := s.client.AbortMultipartUpload(ctx, &s3.AbortMultipartUploadInput{
		Bucket:   aws.String(s.bucket),
		Key:      aws.String(key),
		UploadId: aws.String(uploadID),
	})
	if err != nil {
		return fmt.Errorf("objstore: abort multipart %s: %w", key, err)
	}
	return nil
}
